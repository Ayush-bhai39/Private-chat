import 'package:cloud_firestore/cloud_firestore.dart';

class BlockService {
  final _firestore = FirebaseFirestore.instance;

  Future<void> blockUser(String currentUid, String blockedUid) async {
    final batch = _firestore.batch();

    // 1. Add to blockedUsers list
    batch.update(_firestore.collection('users').doc(currentUid), {
      'blockedUsers': FieldValue.arrayUnion([blockedUid]),
    });

    // 2. Remove mutual follows/followers
    batch.update(_firestore.collection('users').doc(currentUid), {
      'followers': FieldValue.arrayRemove([blockedUid]),
      'following': FieldValue.arrayRemove([blockedUid]),
      'followRequests': FieldValue.arrayRemove([blockedUid]),
    });

    batch.update(_firestore.collection('users').doc(blockedUid), {
      'followers': FieldValue.arrayRemove([currentUid]),
      'following': FieldValue.arrayRemove([currentUid]),
      'followRequests': FieldValue.arrayRemove([currentUid]),
    });

    await batch.commit();
  }

  Future<void> unblockUser(String currentUid, String blockedUid) async {
    await _firestore.collection('users').doc(currentUid).update({
      'blockedUsers': FieldValue.arrayRemove([blockedUid]),
    });
  }

  Future<bool> isBlocked(String currentUid, String otherUid) async {
    final doc = await _firestore.collection('users').doc(currentUid).get();
    if (!doc.exists) return false;
    final blockedUsers = List<String>.from(doc.data()?['blockedUsers'] ?? []);
    return blockedUsers.contains(otherUid);
  }

  Future<bool> isBlockedByEither(String currentUid, String otherUid) async {
    final docs = await Future.wait([
      _firestore.collection('users').doc(currentUid).get(),
      _firestore.collection('users').doc(otherUid).get(),
    ]);

    final currentBlocked = List<String>.from(docs[0].data()?['blockedUsers'] ?? []);
    final otherBlocked = List<String>.from(docs[1].data()?['blockedUsers'] ?? []);

    return currentBlocked.contains(otherUid) || otherBlocked.contains(currentUid);
  }

  Future<List<String>> getBlockedUsers(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return [];
    return List<String>.from(doc.data()?['blockedUsers'] ?? []);
  }
}
