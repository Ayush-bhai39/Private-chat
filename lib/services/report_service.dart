import 'package:cloud_firestore/cloud_firestore.dart';

class ReportService {
  final _firestore = FirebaseFirestore.instance;

  Future<void> reportUser({
    required String reporterUid,
    required String reportedUid,
    required String reason,
    String? messageId,
    String? chatId,
  }) async {
    await _firestore.collection('reports').add({
      'reporterUid': reporterUid,
      'reportedUid': reportedUid,
      'reason': reason,
      'messageId': messageId,
      'chatId': chatId,
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'pending',
    });
  }
}
