import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';
import 'package:secure_chat/models/user_model.dart';
import 'package:secure_chat/models/message_model.dart';
import 'package:secure_chat/models/conversation_model.dart';
import 'package:secure_chat/services/encryption_service.dart';
import 'package:secure_chat/services/user_service.dart';
import 'package:secure_chat/services/mock_config.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';

class ChatService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final UserService _userService = UserService();

  static final Map<String, List<MessageModel>> _mockMessages = {};
  static final Map<String, StreamController<List<MessageModel>>> _mockMessageControllers = {};
  static final StreamController<List<ConversationModel>> _mockConversationController = StreamController<List<ConversationModel>>.broadcast();

  String getChatId(String uid1, String uid2) {
    return uid1.compareTo(uid2) < 0 ? '${uid1}_$uid2' : '${uid2}_$uid1';
  }

  Future<void> sendMessage(
    String recipientUid,
    String plaintext, {
    String? mediaUrl,
    String? mediaType,
    String? repliedMessageId,
    String? repliedMessageSenderUid,
    String? repliedMessageSenderName,
    String? repliedMessageText,
    Uint8List? predefinedAesKey,
    Uint8List? predefinedIv,
    String status = 'sent',
    String? messageId,
  }) async {
    final currentUser = MockConfig.useMock ? null : _auth.currentUser;
    final senderUid = MockConfig.useMock ? "mock_uid_123" : (currentUser?.uid ?? '');
    if (senderUid.isEmpty) throw Exception("User not logged in");

    final recipientUser = await _userService.getUserData(recipientUid);
    if (recipientUser == null) throw Exception("Recipient not found");

    final senderUser = await _userService.getUserData(senderUid);
    if (senderUser == null) throw Exception("Sender not found");

    // 1. Decrypt / Parse Public Keys
    final recipientPubKey = EncryptionService.decodePublicKeyFromPem(recipientUser.publicKey);
    final senderPubKey = EncryptionService.decodePublicKeyFromPem(senderUser.publicKey);

    // 2. Generate random AES key (32 bytes / 256 bits) and IV (16 bytes)
    final random = Random.secure();
    final aesKeyBytes = predefinedAesKey ?? Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256)));
    final ivBytes = predefinedIv ?? Uint8List.fromList(List<int>.generate(16, (_) => random.nextInt(256)));

    // 3. Encrypt message with AES-256-CBC
    final plainTextBytes = utf8.encode(plaintext);
    final cbc = CBCBlockCipher(AESEngine());
    final aesCipher = PaddedBlockCipherImpl(PKCS7Padding(), cbc);
    aesCipher.init(
      true,
      PaddedBlockCipherParameters(
        ParametersWithIV<KeyParameter>(KeyParameter(aesKeyBytes), ivBytes),
        null,
      ),
    );
    final encryptedTextBytes = aesCipher.process(plainTextBytes);

    // Encrypt replied message text if it exists
    String? encryptedRepliedText;
    if (repliedMessageText != null && repliedMessageText.isNotEmpty) {
      try {
        final repliedBytes = utf8.encode(repliedMessageText);
        final cbcRep = CBCBlockCipher(AESEngine());
        final aesCipherRep = PaddedBlockCipherImpl(PKCS7Padding(), cbcRep);
        aesCipherRep.init(
          true,
          PaddedBlockCipherParameters(
            ParametersWithIV<KeyParameter>(KeyParameter(aesKeyBytes), ivBytes),
            null,
          ),
        );
        final encRepBytes = aesCipherRep.process(repliedBytes);
        encryptedRepliedText = base64.encode(encRepBytes);
      } catch (e) {
        print("Error encrypting replied text: $e");
      }
    }

    // 4. Encrypt AES key for Recipient using recipient RSA Public Key
    final recipientRsa = OAEPEncoding(RSAEngine());
    recipientRsa.init(true, PublicKeyParameter<RSAPublicKey>(recipientPubKey));
    final recipientEncKey = recipientRsa.process(aesKeyBytes);

    // 5. Encrypt AES key for Sender using sender RSA Public Key
    final senderRsa = OAEPEncoding(RSAEngine());
    senderRsa.init(true, PublicKeyParameter<RSAPublicKey>(senderPubKey));
    final senderEncKey = senderRsa.process(aesKeyBytes);

    final encryptedKeyMap = {
      recipientUid: base64.encode(recipientEncKey),
      senderUid: base64.encode(senderEncKey),
    };

    final chatId = getChatId(senderUid, recipientUid);
    final finalMessageId = messageId ?? (MockConfig.useMock ? DateTime.now().millisecondsSinceEpoch.toString() : _firestore.collection('chats').doc().id);

    final messageModel = MessageModel(
      id: finalMessageId,
      senderUid: senderUid,
      encryptedMessage: base64.encode(encryptedTextBytes),
      encryptedKey: json.encode(encryptedKeyMap),
      iv: base64.encode(ivBytes),
      timestamp: DateTime.now(),
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      fallbackContent: null, // Disabled insecure symmetric fallback backdoor
      repliedMessageId: repliedMessageId,
      repliedMessageSenderUid: repliedMessageSenderUid,
      repliedMessageSenderName: repliedMessageSenderName,
      encryptedRepliedText: encryptedRepliedText,
      status: status,
    );

    if (MockConfig.useMock) {
      _mockMessages.putIfAbsent(chatId, () => []);
      _mockMessages[chatId]!.insert(0, messageModel);
      
      // Update message stream
      if (_mockMessageControllers.containsKey(chatId)) {
        _mockMessageControllers[chatId]!.add(List.from(_mockMessages[chatId]!));
      }
      
      // Update conversations
      final conversationList = await _getMockConversationsList();
      _mockConversationController.add(conversationList);
      return;
    }

    // Write message document to Firestore
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(finalMessageId)
        .set(messageModel.toMap());

    // Skip conversation updates and push notifications for pending uploads
    if (status == 'uploading') {
      return;
    }

    // Update conversation metadata
    await _firestore.collection('chats').doc(chatId).set(
      {
        'participants': [senderUid, recipientUid],
        'lastMessage': mediaType == 'gif' ? '🎬 Animated GIF' : (mediaType == 'image' ? '📷 Photo' : (mediaType == 'video' ? '🎥 Video' : '🔒 Encrypted message')),
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unreadCount': {
          recipientUid: FieldValue.increment(1),
        }
      },
      SetOptions(merge: true),
    );

    // Send Background Push Notification via FCM HTTP v1
    await _sendPushNotification(recipientUid, senderUid, chatId, finalMessageId, plaintext, mediaType);
  }

  Future<void> updateMediaMessageUrl({
    required String chatId,
    required String messageId,
    required String mediaUrl,
    required String recipientUid,
    required String senderUid,
    required String plaintext,
    required String? mediaType,
  }) async {
    if (MockConfig.useMock) {
      if (_mockMessages.containsKey(chatId)) {
        final messages = _mockMessages[chatId]!;
        final index = messages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          final oldMsg = messages[index];
          messages[index] = oldMsg.copyWith(mediaUrl: mediaUrl, status: 'sent');
          if (_mockMessageControllers.containsKey(chatId)) {
            _mockMessageControllers[chatId]!.add(List.from(messages));
          }
        }
      }
      return;
    }

    // 1. Update message document in Firestore
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({
      'mediaUrl': mediaUrl,
      'status': 'sent',
    });

    // 2. Update conversation metadata
    final lastMsgText = mediaType == 'image' ? '📷 Photo' : (mediaType == 'video' ? '🎥 Video' : '📎 Media File');
    await _firestore.collection('chats').doc(chatId).set(
      {
        'participants': [senderUid, recipientUid],
        'lastMessage': lastMsgText,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unreadCount': {
          recipientUid: FieldValue.increment(1),
        }
      },
      SetOptions(merge: true),
    );

    // 3. Send push notification
    await _sendPushNotification(recipientUid, senderUid, chatId, messageId, plaintext, mediaType);
  }

  Future<void> _sendPushNotification(
    String recipientUid,
    String senderUid,
    String chatId,
    String messageId,
    String plaintext,
    String? mediaType,
  ) async {
    try {
      final recipientUser = await _userService.getUserData(recipientUid);
      if (recipientUser != null && recipientUser.fcmToken.isNotEmpty) {
        final saDoc = await _firestore.collection('metadata').doc('service_account').get();
        if (saDoc.exists && saDoc.data() != null) {
          final saJsonStr = saDoc.data()!['configJson'] as String?;
          if (saJsonStr != null && saJsonStr.isNotEmpty) {
            final saMap = json.decode(saJsonStr) as Map<String, dynamic>;
            final SaProjectId = saMap['project_id'] as String?;
            if (SaProjectId != null && SaProjectId.isNotEmpty) {
              final senderUser = await _userService.getUserData(senderUid);
              final senderName = senderUser?.displayName ?? 'New Message';
              final messageBody = mediaType == 'gif' ? '🎬 Animated GIF' : (mediaType == 'image' ? '📷 Photo' : (mediaType == 'video' ? '🎥 Video' : plaintext));

              // Generate OAuth 2.0 Access Token
              final accountCredentials = ServiceAccountCredentials.fromJson(saJsonStr);
              final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
              final authClient = await clientViaServiceAccount(accountCredentials, scopes);
              final accessToken = authClient.credentials.accessToken.data;
              authClient.close();

              // Send FCM v1 POST Request
              final url = Uri.parse('https://fcm.googleapis.com/v1/projects/$SaProjectId/messages:send');
              final headers = {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $accessToken',
              };
              final body = json.encode({
                'message': {
                  'token': recipientUser.fcmToken,
                  'data': {
                    'title': senderName,
                    'body': messageBody,
                    'click_action': 'FLUTTER_NOTIFICATION_CLICK',
                    'type': 'message',
                    'chatId': chatId,
                    'senderUid': senderUid,
                    'messageId': messageId,
                  },
                  'android': {
                    'priority': 'high',
                  }
                }
              });

              await http.post(url, headers: headers, body: body).timeout(const Duration(seconds: 5));
            }
          }
        }
      }
    } catch (e) {
      print("Error sending FCM v1 notification: $e");
    }
  }

  Future<List<ConversationModel>> _getMockConversationsList() async {
    final conversations = <ConversationModel>[];
    final otherUsers = await _userService.searchUsers(""); // gets Alice and Bob
    for (final otherUser in otherUsers) {
      final chatId = getChatId("mock_uid_123", otherUser.uid);
      final lastMsg = _mockMessages[chatId]?.firstOrNull;
      conversations.add(ConversationModel(
        otherUser: otherUser,
        lastMessage: lastMsg != null 
            ? (lastMsg.mediaType == 'gif' ? '🎬 Animated GIF' : '[Encrypted Message]')
            : 'Tap to start chatting',
        lastMessageTime: lastMsg?.timestamp ?? DateTime.now().subtract(const Duration(minutes: 5)),
      ));
    }
    conversations.sort((a, b) => b.lastMessageTime!.compareTo(a.lastMessageTime!));
    return conversations;
  }

  // Decrypt message content
  Future<String> decryptMessageContent(MessageModel message) async {
    if (message.isDeleted) return '🚫 This message was deleted';

    final currentUser = MockConfig.useMock ? null : _auth.currentUser;
    final uid = MockConfig.useMock ? "mock_uid_123" : (currentUser?.uid ?? '');
    if (uid.isEmpty) return '[Decryption error: Logged out]';

    // Fallback decrypt helper
    String tryFallback() {
      if (message.fallbackContent != null) {
        try {
          final keyMap = json.decode(message.encryptedKey) as Map<String, dynamic>;
          final uids = keyMap.keys.toList();
          if (uids.length == 2) {
            final derivedChatId = getChatId(uids[0], uids[1]);
            return EncryptionService.decryptSymmetric(message.fallbackContent!, derivedChatId);
          }
        } catch (_) {}
      }
      return '[Decryption failed: Missing key]';
    }

    try {
      var privateKeyPem = await _secureStorage.read(key: 'rsa_private_key_$uid');
      if (privateKeyPem == null) {
        // Auto-regenerate keypair for this device since it is completely missing
        try {
          final keyPair = await EncryptionService.generateRSAKeyPair();
          final newPublicPem = EncryptionService.encodePublicKeyToPem(keyPair.publicKey);
          final newPrivatePem = EncryptionService.encodePrivateKeyToPem(keyPair.privateKey);
          await _secureStorage.write(key: 'rsa_private_key_$uid', value: newPrivatePem);
          await _firestore.collection('users').doc(uid).update({'publicKey': newPublicPem});
          privateKeyPem = newPrivatePem;
        } catch (_) {}
        if (privateKeyPem == null) {
          return tryFallback();
        }
      }

      final privateKey = EncryptionService.decodePrivateKeyFromPem(privateKeyPem);

      final keyMap = json.decode(message.encryptedKey) as Map<String, dynamic>;
      final userEncryptedKeyB64 = keyMap[uid] as String?;
      if (userEncryptedKeyB64 == null) return tryFallback();

      final encryptedAesKeyBytes = base64.decode(userEncryptedKeyB64);
      final encryptedTextBytes = base64.decode(message.encryptedMessage);
      final ivBytes = base64.decode(message.iv);

      final rsaEngine = OAEPEncoding(RSAEngine());
      rsaEngine.init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
      final aesKeyBytes = rsaEngine.process(encryptedAesKeyBytes);

      final cbc = CBCBlockCipher(AESEngine());
      final aesCipher = PaddedBlockCipherImpl(PKCS7Padding(), cbc);
      aesCipher.init(
        false,
        PaddedBlockCipherParameters(
          ParametersWithIV<KeyParameter>(KeyParameter(aesKeyBytes), ivBytes),
          null,
        ),
      );
      final decryptedBytes = aesCipher.process(encryptedTextBytes);

      return utf8.decode(decryptedBytes);
    } catch (e) {
      return tryFallback();
    }
  }

  Stream<List<MessageModel>> getMessages(String chatId) {
    if (MockConfig.useMock) {
      final controller = _mockMessageControllers.putIfAbsent(chatId, () {
        final ctrl = StreamController<List<MessageModel>>.broadcast();
        Timer(const Duration(milliseconds: 100), () {
          ctrl.add(_mockMessages[chatId] ?? []);
        });
        return ctrl;
      });
      return controller.stream;
    }
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      final currentUid = _auth.currentUser?.uid ?? '';
      
      // Auto-mark received 'sent' messages as 'delivered'
      final unreadSentDocs = snapshot.docs
          .where((doc) => doc.data()['senderUid'] != currentUid && doc.data()['status'] == 'sent')
          .toList();
          
      if (unreadSentDocs.isNotEmpty) {
        final batch = _firestore.batch();
        for (final doc in unreadSentDocs) {
          batch.update(doc.reference, {'status': 'delivered'});
        }
        batch.commit(); // fire-and-forget
      }

      return snapshot.docs
          .map((doc) {
            final msg = MessageModel.fromMap(doc.data());
            return msg.copyWith(hasPendingWrites: doc.metadata.hasPendingWrites);
          })
          // Filter out messages deleted locally for the current user
          .where((msg) => !msg.deletedForUsers.contains(currentUid))
          .toList();
    });
  }

  Stream<List<ConversationModel>> getConversations() {
    if (MockConfig.useMock) {
      Timer(const Duration(milliseconds: 100), () async {
        final conversationList = await _getMockConversationsList();
        _mockConversationController.add(conversationList);
      });
      return _mockConversationController.stream;
    }
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null) return Stream.value([]);

    return _firestore
        .collection('chats')
        .where('participants', arrayContains: currentUid)
        .snapshots()
        .asyncMap((snapshot) async {
      final conversations = <ConversationModel>[];
      final currentUserData = await _userService.getUserData(currentUid);
      final myBlockedUsers = currentUserData?.blockedUsers ?? [];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final participants = List<String>.from(data['participants'] ?? []);
        final otherUid = participants.firstWhere((id) => id != currentUid, orElse: () => '');
        if (otherUid.isEmpty) continue;

        final otherUser = await _userService.getUserData(otherUid);
        if (otherUser == null) continue;

        // Skip blocked users
        if (myBlockedUsers.contains(otherUid) || otherUser.blockedUsers.contains(currentUid)) {
          continue;
        }

        // Skip conversation details if the other user has a private profile and does not follow the current user
        // (Wait! To make E2EE secure and follow requests functional, if target user is private, we can restrict chats unless following)
        final isFollowing = otherUser.followers.contains(currentUid);
        if (otherUser.isPrivate && !isFollowing) {
          // If already has messages, allow showing. Otherwise skip.
          // Let's keep it simple: allow showing if already chatting, else they wouldn't have created the chat.
        }

        final unreadCountMap = data['unreadCount'] as Map<dynamic, dynamic>?;
        final myUnreadCount = unreadCountMap?[currentUid] as int? ?? 0;

        conversations.add(ConversationModel(
          otherUser: otherUser,
          lastMessage: data['lastMessage'] as String?,
          lastMessageTime: data['lastMessageTime'] is Timestamp
              ? (data['lastMessageTime'] as Timestamp).toDate()
              : null,
          hasUnread: myUnreadCount > 0,
        ));
      }
      conversations.sort((a, b) {
        if (a.lastMessageTime == null) return 1;
        if (b.lastMessageTime == null) return -1;
        return b.lastMessageTime!.compareTo(a.lastMessageTime!);
      });
      return conversations;
    });
  }

  Future<void> editMessage(String recipientUid, String messageId, String newPlaintext) async {
    final senderUid = MockConfig.useMock ? "mock_uid_123" : (_auth.currentUser?.uid ?? '');
    if (senderUid.isEmpty) throw Exception("User not logged in");

    final chatId = getChatId(senderUid, recipientUid);

    if (MockConfig.useMock) {
      if (_mockMessages.containsKey(chatId)) {
        final messages = _mockMessages[chatId]!;
        final idx = messages.indexWhere((m) => m.id == messageId);
        if (idx != -1) {
          messages[idx] = messages[idx].copyWith(
            isEdited: true,
            decryptedText: newPlaintext,
          );
          if (_mockMessageControllers.containsKey(chatId)) {
            _mockMessageControllers[chatId]!.add(List.from(messages));
          }
        }
      }
      return;
    }

    final recipientUser = await _userService.getUserData(recipientUid);
    if (recipientUser == null) throw Exception("Recipient not found");

    final senderUser = await _userService.getUserData(senderUid);
    if (senderUser == null) throw Exception("Sender not found");

    // Re-encrypt message
    final recipientPubKey = EncryptionService.decodePublicKeyFromPem(recipientUser.publicKey);
    final senderPubKey = EncryptionService.decodePublicKeyFromPem(senderUser.publicKey);

    final random = Random.secure();
    final aesKeyBytes = Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256)));
    final ivBytes = Uint8List.fromList(List<int>.generate(16, (_) => random.nextInt(256)));

    final plainTextBytes = utf8.encode(newPlaintext);
    final cbc = CBCBlockCipher(AESEngine());
    final aesCipher = PaddedBlockCipherImpl(PKCS7Padding(), cbc);
    aesCipher.init(
      true,
      PaddedBlockCipherParameters(
        ParametersWithIV<KeyParameter>(KeyParameter(aesKeyBytes), ivBytes),
        null,
      ),
    );
    final encryptedTextBytes = aesCipher.process(plainTextBytes);

    final recipientRsa = OAEPEncoding(RSAEngine());
    recipientRsa.init(true, PublicKeyParameter<RSAPublicKey>(recipientPubKey));
    final recipientEncKey = recipientRsa.process(aesKeyBytes);

    final senderRsa = OAEPEncoding(RSAEngine());
    senderRsa.init(true, PublicKeyParameter<RSAPublicKey>(senderPubKey));
    final senderEncKey = senderRsa.process(aesKeyBytes);

    final encryptedKeyMap = {
      recipientUid: base64.encode(recipientEncKey),
      senderUid: base64.encode(senderEncKey),
    };

    final batch = _firestore.batch();
    batch.update(
      _firestore.collection('chats').doc(chatId).collection('messages').doc(messageId),
      {
        'encryptedMessage': base64.encode(encryptedTextBytes),
        'encryptedKey': json.encode(encryptedKeyMap),
        'iv': base64.encode(ivBytes),
        'isEdited': true,
      },
    );
    batch.update(
      _firestore.collection('chats').doc(chatId),
      {
        'lastMessage': '🔒 Encrypted message (edited)',
        'lastMessageTime': FieldValue.serverTimestamp(),
      },
    );
    await batch.commit();
  }

  Future<void> deleteMessageForEveryone(String recipientUid, String messageId) async {
    final senderUid = MockConfig.useMock ? "mock_uid_123" : (_auth.currentUser?.uid ?? '');
    final chatId = getChatId(senderUid, recipientUid);

    if (MockConfig.useMock) {
      if (_mockMessages.containsKey(chatId)) {
        final messages = _mockMessages[chatId]!;
        final idx = messages.indexWhere((m) => m.id == messageId);
        if (idx != -1) {
          messages[idx] = messages[idx].copyWith(isDeleted: true);
          if (_mockMessageControllers.containsKey(chatId)) {
            _mockMessageControllers[chatId]!.add(List.from(messages));
          }
        }
      }
      return;
    }

    final batch = _firestore.batch();
    batch.update(
      _firestore.collection('chats').doc(chatId).collection('messages').doc(messageId),
      {
        'isDeleted': true,
        'encryptedMessage': '',
        'encryptedKey': '',
        'iv': '',
      },
    );
    batch.update(
      _firestore.collection('chats').doc(chatId),
      {
        'lastMessage': '🚫 This message was deleted',
        'lastMessageTime': FieldValue.serverTimestamp(),
      },
    );
    await batch.commit();
  }

  Future<void> deleteMessageForMe(String recipientUid, String messageId) async {
    final senderUid = MockConfig.useMock ? "mock_uid_123" : (_auth.currentUser?.uid ?? '');
    final chatId = getChatId(senderUid, recipientUid);

    if (MockConfig.useMock) {
      if (_mockMessages.containsKey(chatId)) {
        final messages = _mockMessages[chatId]!;
        final idx = messages.indexWhere((m) => m.id == messageId);
        if (idx != -1) {
          final deletedList = List<String>.from(messages[idx].deletedForUsers);
          deletedList.add(senderUid);
          messages[idx] = messages[idx].copyWith(deletedForUsers: deletedList);
          if (_mockMessageControllers.containsKey(chatId)) {
            _mockMessageControllers[chatId]!.add(List.from(messages));
          }
        }
      }
      return;
    }

    await _firestore.collection('chats').doc(chatId).collection('messages').doc(messageId).update({
      'deletedForUsers': FieldValue.arrayUnion([senderUid])
    });
  }

  Future<void> reactToMessage(String recipientUid, String messageId, String emoji) async {
    final senderUid = MockConfig.useMock ? "mock_uid_123" : (_auth.currentUser?.uid ?? '');
    final chatId = getChatId(senderUid, recipientUid);

    if (MockConfig.useMock) {
      if (_mockMessages.containsKey(chatId)) {
        final messages = _mockMessages[chatId]!;
        final idx = messages.indexWhere((m) => m.id == messageId);
        if (idx != -1) {
          final reactions = Map<String, String>.from(messages[idx].reactions);
          if (reactions[senderUid] == emoji || emoji.isEmpty) {
            reactions.remove(senderUid);
          } else {
            reactions[senderUid] = emoji;
          }
          messages[idx] = messages[idx].copyWith(reactions: reactions);
          if (_mockMessageControllers.containsKey(chatId)) {
            _mockMessageControllers[chatId]!.add(List.from(messages));
          }
        }
      }
      return;
    }

    final docRef = _firestore.collection('chats').doc(chatId).collection('messages').doc(messageId);
    final doc = await docRef.get();
    if (!doc.exists) return;

    final currentReactions = Map<String, String>.from(doc.data()?['reactions'] ?? {});
    if (currentReactions[senderUid] == emoji || emoji.isEmpty) {
      currentReactions.remove(senderUid);
    } else {
      currentReactions[senderUid] = emoji;
    }
    await docRef.update({'reactions': currentReactions});
  }

  Future<void> markChatAsRead(String recipientUid) async {
    final currentUser = MockConfig.useMock ? null : _auth.currentUser;
    final uid = MockConfig.useMock ? "mock_uid_123" : (currentUser?.uid ?? '');
    if (uid.isEmpty) return;

    final chatId = getChatId(uid, recipientUid);
    if (MockConfig.useMock) return;

    // Reset unread count for current user
    await _firestore.collection('chats').doc(chatId).set({
      'unreadCount': {
        uid: 0,
      }
    }, SetOptions(merge: true));

    // Mark all received messages that are not seen yet as 'seen'
    try {
      final unreadQuery = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .where('senderUid', isEqualTo: recipientUid)
          .where('status', isNotEqualTo: 'seen')
          .get();

      if (unreadQuery.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (final doc in unreadQuery.docs) {
          batch.update(doc.reference, {'status': 'seen'});
        }
        await batch.commit();
      }
    } catch (e) {
      print("Error marking messages as seen: $e");
    }
  }

  Future<DecryptedMessage> decryptMessage(MessageModel message) async {
    final text = await decryptMessageContent(message);
    String? repliedText;

    if (message.encryptedRepliedText != null && message.encryptedRepliedText!.isNotEmpty) {
      final currentUser = MockConfig.useMock ? null : _auth.currentUser;
      final uid = MockConfig.useMock ? "mock_uid_123" : (currentUser?.uid ?? '');
      if (uid.isNotEmpty) {
        try {
          var privateKeyPem = await _secureStorage.read(key: 'rsa_private_key_$uid');
          if (privateKeyPem != null) {
            final privateKey = EncryptionService.decodePrivateKeyFromPem(privateKeyPem);
            final keyMap = json.decode(message.encryptedKey) as Map<String, dynamic>;
            final userEncryptedKeyB64 = keyMap[uid] as String?;
            if (userEncryptedKeyB64 != null) {
              final encryptedAesKeyBytes = base64.decode(userEncryptedKeyB64);
              final encryptedRepliedBytes = base64.decode(message.encryptedRepliedText!);
              final ivBytes = base64.decode(message.iv);

              final rsaEngine = OAEPEncoding(RSAEngine());
              rsaEngine.init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
              final aesKeyBytes = rsaEngine.process(encryptedAesKeyBytes);

              final cbc = CBCBlockCipher(AESEngine());
              final aesCipher = PaddedBlockCipherImpl(PKCS7Padding(), cbc);
              aesCipher.init(
                false,
                PaddedBlockCipherParameters(
                  ParametersWithIV<KeyParameter>(KeyParameter(aesKeyBytes), ivBytes),
                  null,
                ),
              );
              final decRepliedBytes = aesCipher.process(encryptedRepliedBytes);
              repliedText = utf8.decode(decRepliedBytes);
            }
          }
        } catch (e) {
          print("Error decrypting replied message: $e");
        }
      }
    }
    return DecryptedMessage(text, repliedText);
  }

  Future<Uint8List> decryptMessageFileBytes(MessageModel message, Uint8List encryptedFileBytes) async {
    final currentUser = MockConfig.useMock ? null : _auth.currentUser;
    final uid = MockConfig.useMock ? "mock_uid_123" : (currentUser?.uid ?? '');
    if (uid.isEmpty) throw Exception("User not logged in");

    var privateKeyPem = await _secureStorage.read(key: 'rsa_private_key_$uid');
    if (privateKeyPem == null) throw Exception("E2EE Private Key not found on device");

    final privateKey = EncryptionService.decodePrivateKeyFromPem(privateKeyPem);
    final keyMap = json.decode(message.encryptedKey) as Map<String, dynamic>;
    final userEncryptedKeyB64 = keyMap[uid] as String?;
    if (userEncryptedKeyB64 == null) throw Exception("No E2EE key for user");

    final encryptedAesKeyBytes = base64.decode(userEncryptedKeyB64);
    final ivBytes = base64.decode(message.iv);

    final rsaEngine = OAEPEncoding(RSAEngine());
    rsaEngine.init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    final aesKeyBytes = rsaEngine.process(encryptedAesKeyBytes);

    return EncryptionService.decryptFileBytes(encryptedFileBytes, aesKeyBytes, ivBytes);
  }
}

class DecryptedMessage {
  final String text;
  final String? repliedText;
  const DecryptedMessage(this.text, this.repliedText);
}
