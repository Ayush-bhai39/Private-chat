import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:secure_chat/models/user_model.dart';
import 'package:secure_chat/services/encryption_service.dart';
import 'package:secure_chat/services/mock_config.dart';

class UserService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static UserModel? _mockUserProfile;
  static final List<UserModel> _mockDbUsers = [
    UserModel(
      uid: "mock_uid_alice",
      email: "alice@secretchat.com",
      displayName: "Alice Smith",
      photoUrl: "https://picsum.photos/201",
      username: "alice",
      publicKey: "-----BEGIN PUBLIC KEY-----\neyJuIjogIjIwMzQ4MzA5NDIiLCAiZSI6ICI2NTUzNyJ9\n-----END PUBLIC KEY-----",
      createdAt: DateTime.now(),
    ),
    UserModel(
      uid: "mock_uid_bob",
      email: "bob@secretchat.com",
      displayName: "Bob Jones",
      photoUrl: "https://picsum.photos/202",
      username: "bob",
      publicKey: "-----BEGIN PUBLIC KEY-----\neyJuIjogIjIwMzQ4MzA5NDIiLCAiZSI6ICI2NTUzNyJ9\n-----END PUBLIC KEY-----",
      createdAt: DateTime.now(),
    ),
  ];

  Future<UserModel?> getUserData(String uid) async {
    if (MockConfig.useMock) {
      if (uid == "mock_uid_123") return _mockUserProfile;
      return _mockDbUsers.firstWhere((u) => u.uid == uid, orElse: () => _mockDbUsers.first);
    }
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists || doc.data() == null) return null;
      return UserModel.fromMap(doc.data()!);
    } catch (e) {
      print("Error getting user data: $e");
      return null;
    }
  }

  Future<bool> isUsernameAvailable(String username) async {
    if (MockConfig.useMock) {
      return !_mockDbUsers.any((u) => u.username == username.toLowerCase());
    }
    try {
      final doc = await _firestore.collection('usernames').doc(username).get();
      return !doc.exists;
    } catch (e) {
      return false;
    }
  }

  Future<void> createUser({
    required String uid,
    required String email,
    required String displayName,
    required String photoUrl,
    required String username,
  }) async {
    if (MockConfig.useMock) {
      final keys = await EncryptionService.generateRSAKeyPairInBackground();
      final publicKeyPem = keys['publicKey']!;
      final privateKeyPem = keys['privateKey']!;

      await _secureStorage.write(key: 'rsa_private_key_$uid', value: privateKeyPem);

      _mockUserProfile = UserModel(
        uid: uid,
        email: email,
        displayName: displayName,
        photoUrl: photoUrl,
        username: username,
        publicKey: publicKeyPem,
        createdAt: DateTime.now(),
      );
      return;
    }

    final keys = await EncryptionService.generateRSAKeyPairInBackground();
    final publicKeyPem = keys['publicKey']!;
    final privateKeyPem = keys['privateKey']!;

    await _secureStorage.write(key: 'rsa_private_key_$uid', value: privateKeyPem);

    final userModel = UserModel(
      uid: uid,
      email: email,
      displayName: displayName,
      photoUrl: photoUrl,
      username: username,
      publicKey: publicKeyPem,
      createdAt: DateTime.now(),
    );

    final batch = _firestore.batch();
    batch.set(_firestore.collection('users').doc(uid), userModel.toMap());
    batch.set(_firestore.collection('usernames').doc(username), {'uid': uid});
    await batch.commit();
  }

  Future<List<UserModel>> searchUsers(String query) async {
    if (MockConfig.useMock) {
      if (query.isEmpty) return [];
      return _mockDbUsers
          .where((u) => u.username.toLowerCase().contains(query.toLowerCase()))
          .toList();
    }
    if (query.isEmpty) return [];
    final lowercaseQuery = query.toLowerCase();
    final snapshot = await _firestore
        .collection('users')
        .where('username', isGreaterThanOrEqualTo: lowercaseQuery)
        .where('username', isLessThanOrEqualTo: '$lowercaseQuery\uf8ff')
        .get();

    return snapshot.docs.map((doc) => UserModel.fromMap(doc.data())).toList();
  }

  Future<void> updateProfile({
    required String uid,
    required String displayName,
    required String photoUrl,
  }) async {
    if (MockConfig.useMock) {
      if (_mockUserProfile != null) {
        _mockUserProfile = _mockUserProfile!.copyWith(
          displayName: displayName,
          photoUrl: photoUrl,
        );
      }
      return;
    }
    await _firestore.collection('users').doc(uid).update({
      'displayName': displayName,
      'photoUrl': photoUrl,
    });
  }

  Future<void> toggleAccountPrivacy(String uid, bool isPrivate) async {
    if (MockConfig.useMock) {
      if (_mockUserProfile != null) {
        _mockUserProfile = _mockUserProfile!.copyWith(isPrivate: isPrivate);
      }
      return;
    }
    await _firestore.collection('users').doc(uid).update({'isPrivate': isPrivate});
  }

  Future<void> followUser(String currentUid, String targetUid) async {
    if (MockConfig.useMock) {
      final targetIdx = _mockDbUsers.indexWhere((u) => u.uid == targetUid);
      if (targetIdx != -1) {
        final target = _mockDbUsers[targetIdx];
        if (target.isPrivate) {
          final requests = List<String>.from(target.followRequests);
          if (!requests.contains(currentUid)) {
            requests.add(currentUid);
            _mockDbUsers[targetIdx] = target.copyWith(followRequests: requests);
          }
        } else {
          final followers = List<String>.from(target.followers);
          if (!followers.contains(currentUid)) {
            followers.add(currentUid);
            _mockDbUsers[targetIdx] = target.copyWith(followers: followers);
          }
          if (_mockUserProfile != null) {
            final following = List<String>.from(_mockUserProfile!.following);
            if (!following.contains(targetUid)) {
              following.add(targetUid);
              _mockUserProfile = _mockUserProfile!.copyWith(following: following);
            }
          }
        }
      }
      return;
    }

    final targetDoc = await _firestore.collection('users').doc(targetUid).get();
    if (!targetDoc.exists) return;
    final target = UserModel.fromMap(targetDoc.data()!);

    if (target.isPrivate) {
      await _firestore.collection('users').doc(targetUid).update({
        'followRequests': FieldValue.arrayUnion([currentUid])
      });
    } else {
      final batch = _firestore.batch();
      batch.update(_firestore.collection('users').doc(targetUid), {
        'followers': FieldValue.arrayUnion([currentUid])
      });
      batch.update(_firestore.collection('users').doc(currentUid), {
        'following': FieldValue.arrayUnion([targetUid])
      });
      await batch.commit();
    }
  }

  Future<void> unfollowUser(String currentUid, String targetUid) async {
    if (MockConfig.useMock) {
      final targetIdx = _mockDbUsers.indexWhere((u) => u.uid == targetUid);
      if (targetIdx != -1) {
        final target = _mockDbUsers[targetIdx];
        final followers = List<String>.from(target.followers)..remove(currentUid);
        final requests = List<String>.from(target.followRequests)..remove(currentUid);
        _mockDbUsers[targetIdx] = target.copyWith(followers: followers, followRequests: requests);
        
        if (_mockUserProfile != null) {
          final following = List<String>.from(_mockUserProfile!.following)..remove(targetUid);
          _mockUserProfile = _mockUserProfile!.copyWith(following: following);
        }
      }
      return;
    }

    final batch = _firestore.batch();
    batch.update(_firestore.collection('users').doc(targetUid), {
      'followers': FieldValue.arrayRemove([currentUid]),
      'followRequests': FieldValue.arrayRemove([currentUid])
    });
    batch.update(_firestore.collection('users').doc(currentUid), {
      'following': FieldValue.arrayRemove([targetUid])
    });
    await batch.commit();
  }

  Future<void> acceptFollowRequest(String currentUid, String requesterUid) async {
    if (MockConfig.useMock) {
      if (_mockUserProfile != null) {
        final requests = List<String>.from(_mockUserProfile!.followRequests)..remove(requesterUid);
        final followers = List<String>.from(_mockUserProfile!.followers);
        if (!followers.contains(requesterUid)) followers.add(requesterUid);
        _mockUserProfile = _mockUserProfile!.copyWith(followRequests: requests, followers: followers);
      }
      final requesterIdx = _mockDbUsers.indexWhere((u) => u.uid == requesterUid);
      if (requesterIdx != -1) {
        final requester = _mockDbUsers[requesterIdx];
        final following = List<String>.from(requester.following);
        if (!following.contains(currentUid)) following.add(currentUid);
        _mockDbUsers[requesterIdx] = requester.copyWith(following: following);
      }
      return;
    }

    final batch = _firestore.batch();
    batch.update(_firestore.collection('users').doc(currentUid), {
      'followRequests': FieldValue.arrayRemove([requesterUid]),
      'followers': FieldValue.arrayUnion([requesterUid])
    });
    batch.update(_firestore.collection('users').doc(requesterUid), {
      'following': FieldValue.arrayUnion([currentUid])
    });
    await batch.commit();
  }

  Future<void> declineFollowRequest(String currentUid, String requesterUid) async {
    if (MockConfig.useMock) {
      if (_mockUserProfile != null) {
        final requests = List<String>.from(_mockUserProfile!.followRequests)..remove(requesterUid);
        _mockUserProfile = _mockUserProfile!.copyWith(followRequests: requests);
      }
      return;
    }
    await _firestore.collection('users').doc(currentUid).update({
      'followRequests': FieldValue.arrayRemove([requesterUid])
    });
  }

  Future<List<UserModel>> getFollowRequests(String uid) async {
    if (MockConfig.useMock) {
      if (_mockUserProfile == null) return [];
      final list = <UserModel>[];
      for (final reqUid in _mockUserProfile!.followRequests) {
        final u = _mockDbUsers.firstWhere((usr) => usr.uid == reqUid, orElse: () => _mockDbUsers.first);
        list.add(u);
      }
      return list;
    }

    final userDoc = await _firestore.collection('users').doc(uid).get();
    if (!userDoc.exists) return [];
    final user = UserModel.fromMap(userDoc.data()!);
    
    final list = <UserModel>[];
    for (final reqUid in user.followRequests) {
      final reqDoc = await _firestore.collection('users').doc(reqUid).get();
      if (reqDoc.exists) {
        list.add(UserModel.fromMap(reqDoc.data()!));
      }
    }
    return list;
  }
}
