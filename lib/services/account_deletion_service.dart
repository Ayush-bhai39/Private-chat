import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AccountDeletionService {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _secureStorage = const FlutterSecureStorage();

  Future<void> deleteAccount(String uid, String username) async {
    // 1. Delete all messages and conversations where user is participant
    final chatSnaps = await _firestore
        .collection('chats')
        .where('participants', arrayContains: uid)
        .get();

    for (final chatDoc in chatSnaps.docs) {
      final chatId = chatDoc.id;
      
      // Delete all messages inside this conversation
      final messagesSnap = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();

      final batch = _firestore.batch();
      for (final msgDoc in messagesSnap.docs) {
        batch.delete(msgDoc.reference);
      }
      // Also delete the chat document itself
      batch.delete(chatDoc.reference);
      await batch.commit();
    }

    // 2. Delete all stories by the user
    final storySnaps = await _firestore
        .collection('stories')
        .where('authorUid', isEqualTo: uid)
        .get();

    final storyBatch = _firestore.batch();
    for (final storyDoc in storySnaps.docs) {
      storyBatch.delete(storyDoc.reference);
    }
    await storyBatch.commit();

    // 3. Delete user's active notes
    await _firestore.collection('notes').doc(uid).delete();

    // 4. Remove uid from followers/following lists of all other users
    final followersSnaps = await _firestore
        .collection('users')
        .where('followers', arrayContains: uid)
        .get();

    final followersBatch = _firestore.batch();
    for (final userDoc in followersSnaps.docs) {
      followersBatch.update(userDoc.reference, {
        'followers': FieldValue.arrayRemove([uid]),
      });
    }
    await followersBatch.commit();

    final followingSnaps = await _firestore
        .collection('users')
        .where('following', arrayContains: uid)
        .get();

    final followingBatch = _firestore.batch();
    for (final userDoc in followingSnaps.docs) {
      followingBatch.update(userDoc.reference, {
        'following': FieldValue.arrayRemove([uid]),
      });
    }
    await followingBatch.commit();

    final requestsSnaps = await _firestore
        .collection('users')
        .where('followRequests', arrayContains: uid)
        .get();

    final requestsBatch = _firestore.batch();
    for (final userDoc in requestsSnaps.docs) {
      requestsBatch.update(userDoc.reference, {
        'followRequests': FieldValue.arrayRemove([uid]),
      });
    }
    await requestsBatch.commit();

    // 5. Delete username document from the usernames directory
    if (username.isNotEmpty) {
      await _firestore.collection('usernames').doc(username).delete();
    }

    // 6. Delete user profile document from users collection
    await _firestore.collection('users').doc(uid).delete();

    // 7. Delete local RSA private key and secure keys
    await _secureStorage.delete(key: 'rsa_private_key_$uid');
    await _secureStorage.delete(key: 'incognito_keyboard_$uid');
    await _secureStorage.delete(key: 'app_pin_$uid');

    // 8. Delete user from Firebase Auth
    final user = _auth.currentUser;
    if (user != null) {
      await user.delete();
    }
  }

  Future<Map<String, dynamic>> exportUserData(String uid) async {
    final Map<String, dynamic> exportedData = {};

    // 1. Export user profile doc
    final userDoc = await _firestore.collection('users').doc(uid).get();
    if (userDoc.exists) {
      exportedData['profile'] = userDoc.data();
    }

    // 2. Export user notes
    final noteDoc = await _firestore.collection('notes').doc(uid).get();
    if (noteDoc.exists) {
      exportedData['note'] = noteDoc.data();
    }

    // 3. Export stories by user
    final storySnaps = await _firestore
        .collection('stories')
        .where('authorUid', isEqualTo: uid)
        .get();
    exportedData['stories'] = storySnaps.docs.map((d) => d.data()).toList();

    // 4. Export conversations and messages metadata (the encrypted payloads themselves)
    final chatSnaps = await _firestore
        .collection('chats')
        .where('participants', arrayContains: uid)
        .get();

    final List<Map<String, dynamic>> chatsList = [];
    for (final chatDoc in chatSnaps.docs) {
      final chatId = chatDoc.id;
      final chatData = chatDoc.data();
      
      final messagesSnap = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();

      chatData['messages'] = messagesSnap.docs.map((d) => d.data()).toList();
      chatsList.add(chatData);
    }
    exportedData['chats'] = chatsList;

    return exportedData;
  }
}
