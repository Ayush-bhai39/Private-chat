import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:secure_chat/models/call_model.dart';
import 'package:secure_chat/models/user_model.dart';
import 'package:secure_chat/services/encryption_service.dart';
import 'package:secure_chat/services/user_service.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';

class CallService {
  CallService._();
  static final CallService instance = CallService._();
  factory CallService() => instance;

  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _userService = UserService();
  final _secureStorage = const FlutterSecureStorage();

  // WebRTC state
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  String? _currentCallId;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isOnHold = false;
  bool _isVideoEnabled = true;
  Timer? _timeoutTimer;
  
  // WebRTC candidate queue to avoid race conditions
  final List<RTCIceCandidate> _remoteCandidatesQueue = [];
  bool _remoteDescriptionSet = false;

  // Connection constraints for secure DTLS-SRTP key agreement
  static final Map<String, dynamic> _connectionConstraints = {
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
    ],
  };

  // Firestore listeners
  StreamSubscription? _callDocListener;
  StreamSubscription? _candidatesListener;

  // UI callbacks
  Function(MediaStream)? onLocalStream;
  Function(MediaStream)? onRemoteStream;
  Function(CallModel)? onCallStateChanged;
  Function()? onCallEnded;

  // Public getters
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isOnHold => _isOnHold;
  bool get isVideoEnabled => _isVideoEnabled;
  String? get currentCallId => _currentCallId;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  // STUN servers (Google's free STUN servers)
  static final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {
        'urls': [
          'stun:stun1.l.google.com:19302',
          'stun:stun2.l.google.com:19302',
        ]
      },
    ],
    'sdpSemantics': 'unified-plan',
  };

  // ─────────────────────────────────────────────
  //  START CALL (Caller side)
  // ─────────────────────────────────────────────
  Future<String> startCall(UserModel caller, UserModel callee, String type) async {
    final callId = '${caller.uid}_${callee.uid}_${DateTime.now().millisecondsSinceEpoch}';
    _currentCallId = callId;
    _isMuted = false;
    _isSpeakerOn = false;
    _isOnHold = false;
    _isVideoEnabled = type == 'video';

    try {
      // Ensure local private and public keys are initialized
      await _ensureLocalKeysExist(caller.uid);

      // Fetch the latest profiles directly from Firestore to ensure public keys are loaded
      final latestCaller = await _userService.getUserData(caller.uid);
      final latestCallee = await _userService.getUserData(callee.uid);

      if (latestCaller == null || latestCaller.publicKey.isEmpty) {
        throw Exception("Your profile key is not set. Please restart the app to initialize.");
      }
      if (latestCallee == null || latestCallee.publicKey.isEmpty) {
        throw Exception("decodePublicKey: Contact has not set up E2EE calling yet.");
      }

      // Initialize WebRTC
      await _initPeerConnection(callId);
      await _getUserMedia(type == 'video');

      // Add local tracks to peer connection
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      // Create SDP offer
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': type == 'video',
      });
      await _peerConnection!.setLocalDescription(offer);

      // Encrypt the SDP offer for both users
      final calleePublicKey = EncryptionService.decodePublicKeyFromPem(latestCallee.publicKey);
      final callerPublicKey = EncryptionService.decodePublicKeyFromPem(latestCaller.publicKey);

      final encryptedForCallee = EncryptionService.encryptMessage(offer.sdp!, calleePublicKey);
      final encryptedForCaller = EncryptionService.encryptMessage(offer.sdp!, callerPublicKey);

      // Create call document
      final callModel = CallModel(
        callId: callId,
        callerUid: caller.uid,
        calleeUid: callee.uid,
        callerName: caller.displayName,
        calleeName: callee.displayName,
        callerPhotoUrl: caller.photoUrl,
        calleePhotoUrl: callee.photoUrl,
        callerFcmToken: caller.fcmToken,
        calleeFcmToken: callee.fcmToken,
        type: type,
        status: 'ringing',
        encryptedOffer: encryptedForCallee['encryptedMessage']!,
        offerIv: encryptedForCallee['iv']!,
        encryptedOfferKey: {
          callee.uid: encryptedForCallee['encryptedKey']!,
          caller.uid: encryptedForCaller['encryptedKey']!,
        },
        createdAt: DateTime.now(),
      );

      await _firestore.collection('calls').doc(callId).set(callModel.toMap());

      // Send push notification to callee
      _sendCallNotification(caller, callee, callId, type);

      // Listen for answer
      _listenForAnswer(callId, caller);

      // Listen for ICE candidates
      _listenForCandidates(callId);

      // 45-second ringing timeout
      _timeoutTimer = Timer(const Duration(seconds: 45), () {
        _firestore.collection('calls').doc(callId).get().then((doc) {
          if (doc.exists) {
            final status = doc.data()?['status'] as String? ?? '';
            if (status == 'ringing') {
              endCall(status: 'missed');
            }
          }
        });
      });

      return callId;
    } catch (e) {
      print('Error starting call: $e');
      await endCall(status: 'ended');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────
  //  ANSWER CALL (Callee side)
  // ─────────────────────────────────────────────
  Future<void> answerCall(CallModel call) async {
    _currentCallId = call.callId;
    _isMuted = false;
    _isSpeakerOn = false;
    _isOnHold = false;
    _isVideoEnabled = call.type == 'video';

    try {
      // Initialize WebRTC
      await _initPeerConnection(call.callId);
      await _getUserMedia(call.type == 'video');

      // Add local tracks
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      // Decrypt the SDP offer
      final privateKey = await _getPrivateKey();
      final myUid = _auth.currentUser!.uid;
      final myEncryptedKey = call.encryptedOfferKey[myUid] ?? '';

      if (myEncryptedKey.isEmpty) {
        throw Exception('No encrypted offer key found for current user');
      }

      final decryptedSdp = EncryptionService.decryptMessage(
        call.encryptedOffer,
        myEncryptedKey,
        call.offerIv,
        privateKey,
      );

      // Set remote description (the offer)
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(decryptedSdp, 'offer'),
      );
      _remoteDescriptionSet = true;
      _processQueuedCandidates();

      // Create answer
      final answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': call.type == 'video',
      });
      await _peerConnection!.setLocalDescription(answer);

      // Encrypt the answer for both users
      final callerUser = await _userService.getUserData(call.callerUid);
      final calleeUser = await _userService.getUserData(call.calleeUid);

      if (callerUser == null || calleeUser == null) {
        throw Exception('Could not fetch user data for encryption');
      }

      final callerPublicKey = EncryptionService.decodePublicKeyFromPem(callerUser.publicKey);
      final calleePublicKey = EncryptionService.decodePublicKeyFromPem(calleeUser.publicKey);

      final encryptedForCaller = EncryptionService.encryptMessage(answer.sdp!, callerPublicKey);
      final encryptedForCallee = EncryptionService.encryptMessage(answer.sdp!, calleePublicKey);

      // Update Firestore with answer
      await _firestore.collection('calls').doc(call.callId).update({
        'encryptedAnswer': encryptedForCaller['encryptedMessage'],
        'answerIv': encryptedForCaller['iv'],
        'encryptedAnswerKey': {
          call.callerUid: encryptedForCaller['encryptedKey'],
          call.calleeUid: encryptedForCallee['encryptedKey'],
        },
        'status': 'answered',
        'answeredAt': FieldValue.serverTimestamp(),
      });

      // Listen for ICE candidates
      _listenForCandidates(call.callId);

    } catch (e) {
      print('Error answering call: $e');
      await endCall(status: 'ended');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────
  //  END CALL
  // ─────────────────────────────────────────────
  Future<void> endCall({String status = 'ended'}) async {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;

    // Cancel Firestore listeners
    await _callDocListener?.cancel();
    _callDocListener = null;
    await _candidatesListener?.cancel();
    _candidatesListener = null;

    // Stop local media tracks
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await track.stop();
      }
      await _localStream!.dispose();
      _localStream = null;
    }

    // Stop remote media tracks
    if (_remoteStream != null) {
      for (final track in _remoteStream!.getTracks()) {
        await track.stop();
      }
      await _remoteStream!.dispose();
      _remoteStream = null;
    }

    // Close peer connection
    if (_peerConnection != null) {
      await _peerConnection!.close();
      _peerConnection = null;
    }

    // Update Firestore
    if (_currentCallId != null) {
      try {
        final docRef = _firestore.collection('calls').doc(_currentCallId!);
        final doc = await docRef.get();
        if (doc.exists) {
          await docRef.update({
            'status': status,
            'endedAt': FieldValue.serverTimestamp(),
          });

          // Cleanup: delete call doc and candidates after delay
          _cleanupCallDocuments(_currentCallId!);
        }
      } catch (e) {
        print('Error updating call status: $e');
      }
    }

    _currentCallId = null;
    _isMuted = false;
    _isSpeakerOn = false;
    _isOnHold = false;
    _isVideoEnabled = true;
    _remoteCandidatesQueue.clear();
    _remoteDescriptionSet = false;

    onCallEnded?.call();
  }

  // ─────────────────────────────────────────────
  //  DECLINE CALL
  // ─────────────────────────────────────────────
  Future<void> declineCall(String callId) async {
    try {
      await _firestore.collection('calls').doc(callId).update({
        'status': 'declined',
        'endedAt': FieldValue.serverTimestamp(),
      });
      _cleanupCallDocuments(callId);
    } catch (e) {
      print('Error declining call: $e');
    }
  }

  // ─────────────────────────────────────────────
  //  CALL CONTROLS
  // ─────────────────────────────────────────────
  void toggleMute() {
    _isMuted = !_isMuted;
    if (_localStream != null) {
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = !_isMuted;
      }
    }
  }

  void toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
    if (_localStream != null) {
      for (final track in _localStream!.getAudioTracks()) {
        track.enableSpeakerphone(_isSpeakerOn);
      }
    }
  }

  void toggleHold() {
    _isOnHold = !_isOnHold;
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        track.enabled = !_isOnHold;
      }
    }
    // Update Firestore hold state
    if (_currentCallId != null) {
      _firestore.collection('calls').doc(_currentCallId!).update({
        'isOnHold': _isOnHold,
      }).catchError((e) => print('Error updating hold state: $e'));
    }
  }

  void toggleVideo() {
    _isVideoEnabled = !_isVideoEnabled;
    if (_localStream != null) {
      for (final track in _localStream!.getVideoTracks()) {
        track.enabled = _isVideoEnabled;
      }
    }
  }

  Future<void> switchCamera() async {
    if (_localStream != null) {
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        await Helper.switchCamera(videoTracks.first);
      }
    }
  }

  // ─────────────────────────────────────────────
  //  INCOMING CALL STREAM
  // ─────────────────────────────────────────────
  Stream<CallModel?> getIncomingCalls() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    return _firestore
        .collection('calls')
        .where('calleeUid', isEqualTo: uid)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      return CallModel.fromMap(snapshot.docs.first.data());
    });
  }

  // ─────────────────────────────────────────────
  //  PRIVATE: Initialize WebRTC Peer Connection
  // ─────────────────────────────────────────────
  Future<void> _initPeerConnection(String callId) async {
    _remoteCandidatesQueue.clear();
    _remoteDescriptionSet = false;
    _peerConnection = await createPeerConnection(_iceServers, _connectionConstraints);
    final currentUid = _auth.currentUser?.uid ?? '';

    // Handle ICE candidates — write to Firestore for the remote peer
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      _firestore
          .collection('calls')
          .doc(callId)
          .collection('candidates')
          .add({
        'candidate': candidate.toMap(),
        'senderUid': currentUid,
        'timestamp': FieldValue.serverTimestamp(),
      }).catchError((e) => print('Error adding ICE candidate: $e'));
    };

    // Handle remote track (audio/video from the other user)
    _peerConnection!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        onRemoteStream?.call(_remoteStream!);
      }
    };

    // Handle connection state changes
    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      print('WebRTC connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        // Give a short grace period for reconnection before ending
        Future.delayed(const Duration(seconds: 5), () {
          if (_peerConnection?.connectionState ==
                  RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
              _peerConnection?.connectionState ==
                  RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
            endCall();
          }
        });
      }
    };
  }

  // ─────────────────────────────────────────────
  //  PRIVATE: Request permissions & Get User Media
  // ─────────────────────────────────────────────
  Future<void> _getUserMedia(bool video) async {
    // On mobile, explicitly request permissions before getUserMedia.
    // On desktop (Windows/Linux/macOS), permissions are granted at OS level.
    if (Platform.isAndroid || Platform.isIOS) {
      final permissionsToRequest = <Permission>[Permission.microphone];
      if (video) permissionsToRequest.add(Permission.camera);

      final statuses = await permissionsToRequest.request();

      final micStatus = statuses[Permission.microphone];
      if (micStatus != PermissionStatus.granted) {
        if (micStatus == PermissionStatus.permanentlyDenied) {
          await openAppSettings();
        }
        throw Exception('Microphone permission is required for calls.');
      }

      if (video) {
        final camStatus = statuses[Permission.camera];
        if (camStatus != PermissionStatus.granted) {
          if (camStatus == PermissionStatus.permanentlyDenied) {
            await openAppSettings();
          }
          throw Exception('Camera permission is required for video calls.');
        }
      }
    }

    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': video
          ? (Platform.isAndroid || Platform.isIOS
              ? {
                  'mandatory': {
                    'minWidth': 640,
                    'minHeight': 480,
                    'minFrameRate': 30,
                  },
                  'facingMode': 'user',
                  'optional': [],
                }
              : true)
          : false,
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      onLocalStream?.call(_localStream!);
    } catch (e) {
      print("getUserMedia Error: $e");
      rethrow;
    }
  }

  // ─────────────────────────────────────────────
  //  PRIVATE: Listen for SDP Answer (Caller side)
  // ─────────────────────────────────────────────
  void _listenForAnswer(String callId, UserModel caller) {
    _callDocListener = _firestore
        .collection('calls')
        .doc(callId)
        .snapshots()
        .listen((snapshot) async {
      if (!snapshot.exists) {
        endCall();
        return;
      }

      final data = snapshot.data()!;
      final status = data['status'] as String? ?? '';
      final encryptedAnswer = data['encryptedAnswer'] as String? ?? '';

      // Notify UI of state changes
      final callModel = CallModel.fromMap(data);
      onCallStateChanged?.call(callModel);

      if (status == 'declined' || status == 'ended' || status == 'missed') {
        endCall(status: status);
        return;
      }

      if (status == 'answered' && encryptedAnswer.isNotEmpty) {
        try {
          // Decrypt the answer
          final privateKey = await _getPrivateKey();
          final answerIv = data['answerIv'] as String? ?? '';
          final encryptedAnswerKey = Map<String, String>.from(data['encryptedAnswerKey'] ?? {});
          final myKey = encryptedAnswerKey[caller.uid] ?? '';

          if (myKey.isEmpty || answerIv.isEmpty) return;

          final decryptedSdp = EncryptionService.decryptMessage(
            encryptedAnswer,
            myKey,
            answerIv,
            privateKey,
          );

          // Set remote description
          if (_peerConnection != null) {
            await _peerConnection!.setRemoteDescription(
              RTCSessionDescription(decryptedSdp, 'answer'),
            );
            _remoteDescriptionSet = true;
            _processQueuedCandidates();
          }

          // Cancel timeout
          _timeoutTimer?.cancel();
          _timeoutTimer = null;

          // Stop listening for answer updates (we got what we need)
          await _callDocListener?.cancel();
          _callDocListener = null;
        } catch (e) {
          print('Error processing answer: $e');
        }
      }
    });
  }

  // ─────────────────────────────────────────────
  //  PRIVATE: Listen for ICE Candidates
  // ─────────────────────────────────────────────
  void _listenForCandidates(String callId) {
    final currentUid = _auth.currentUser?.uid ?? '';

    _candidatesListener = _firestore
        .collection('calls')
        .doc(callId)
        .collection('candidates')
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data == null) continue;

          final senderUid = data['senderUid'] as String? ?? '';
          if (senderUid == currentUid) continue; // Skip own candidates

          final candidateMap = data['candidate'] as Map<String, dynamic>?;
          if (candidateMap == null) continue;

          try {
            final candidate = RTCIceCandidate(
              candidateMap['candidate'] as String?,
              candidateMap['sdpMid'] as String?,
              candidateMap['sdpMLineIndex'] as int?,
            );
            if (_remoteDescriptionSet && _peerConnection != null) {
              _peerConnection!.addCandidate(candidate);
            } else {
              _remoteCandidatesQueue.add(candidate);
            }
          } catch (e) {
            print('Error adding remote ICE candidate: $e');
          }
        }
      }
    });
  }

  void _processQueuedCandidates() {
    if (_peerConnection != null && _remoteDescriptionSet) {
      for (final candidate in _remoteCandidatesQueue) {
        _peerConnection!.addCandidate(candidate).catchError((e) {
          print('Error adding queued ICE candidate: $e');
        });
      }
      _remoteCandidatesQueue.clear();
    }
  }

  Future<String> _ensureLocalKeysExist(String uid) async {
    String? privateKeyPem = await _secureStorage.read(key: 'rsa_private_key_$uid');

    if (privateKeyPem == null) {
      try {
        final keyPair = await EncryptionService.generateRSAKeyPair();
        final newPublicPem = EncryptionService.encodePublicKeyToPem(keyPair.publicKey);
        final newPrivatePem = EncryptionService.encodePrivateKeyToPem(keyPair.privateKey);
        
        await _secureStorage.write(key: 'rsa_private_key_$uid', value: newPrivatePem);
        await _firestore.collection('users').doc(uid).update({'publicKey': newPublicPem});
        
        privateKeyPem = newPrivatePem;
      } catch (e) {
        print("Error generating new keypair in CallService: $e");
      }
    }

    if (privateKeyPem == null) {
      throw Exception("Could not initialize security keys for calling");
    }

    return privateKeyPem;
  }

  // ─────────────────────────────────────────────
  //  PRIVATE: Get RSA Private Key
  // ─────────────────────────────────────────────
  Future<dynamic> _getPrivateKey() async {
    final uid = _auth.currentUser!.uid;
    final privateKeyPem = await _ensureLocalKeysExist(uid);
    return EncryptionService.decodePrivateKeyFromPem(privateKeyPem);
  }

  // ─────────────────────────────────────────────
  //  PRIVATE: Send FCM Call Notification
  // ─────────────────────────────────────────────
  Future<void> _sendCallNotification(
    UserModel caller,
    UserModel callee,
    String callId,
    String type,
  ) async {
    try {
      if (callee.fcmToken.isEmpty) return;

      final saDoc = await _firestore.collection('metadata').doc('service_account').get();
      if (!saDoc.exists || saDoc.data() == null) return;

      final saJsonStr = saDoc.data()!['configJson'] as String?;
      if (saJsonStr == null || saJsonStr.isEmpty) return;

      final saMap = json.decode(saJsonStr) as Map<String, dynamic>;
      final projectId = saMap['project_id'] as String?;
      if (projectId == null || projectId.isEmpty) return;

      // Generate OAuth 2.0 Access Token
      final accountCredentials = ServiceAccountCredentials.fromJson(saJsonStr);
      final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
      final authClient = await clientViaServiceAccount(accountCredentials, scopes);
      final accessToken = authClient.credentials.accessToken.data;
      authClient.close();

      // Send FCM v1 POST Request
      final url = Uri.parse(
        'https://fcm.googleapis.com/v1/projects/$projectId/messages:send',
      );
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      };
      final body = json.encode({
        'message': {
          'token': callee.fcmToken,
          'data': {
            'title': caller.displayName,
            'body': '${type == 'video' ? '📹' : '📞'} Incoming $type call',
            'type': 'call',
            'callId': callId,
            'callerUid': caller.uid,
            'callerName': caller.displayName,
            'callType': type,
          },
          'android': {
            'priority': 'high',
          },
        },
      });

      await http.post(url, headers: headers, body: body).timeout(
        const Duration(seconds: 5),
      );
    } catch (e) {
      print('Error sending call notification: $e');
    }
  }

  // ─────────────────────────────────────────────
  //  PRIVATE: Cleanup Firestore Call Documents
  // ─────────────────────────────────────────────
  Future<void> _cleanupCallDocuments(String callId) async {
    // Delay cleanup to let both sides process the end state
    Future.delayed(const Duration(seconds: 10), () async {
      try {
        // Delete ICE candidates subcollection
        final candidatesSnapshot = await _firestore
            .collection('calls')
            .doc(callId)
            .collection('candidates')
            .get();

        final batch = _firestore.batch();
        for (final doc in candidatesSnapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();

        // Delete call document
        await _firestore.collection('calls').doc(callId).delete();
      } catch (e) {
        print('Error cleaning up call documents: $e');
      }
    });
  }
}
