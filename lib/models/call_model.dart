import 'package:cloud_firestore/cloud_firestore.dart';

class CallModel {
  final String callId;
  final String callerUid;
  final String calleeUid;
  final String callerName;
  final String calleeName;
  final String callerPhotoUrl;
  final String calleePhotoUrl;
  final String callerFcmToken;
  final String calleeFcmToken;
  final String type;
  final String status;
  final String encryptedOffer;
  final String encryptedAnswer;
  final String offerIv;
  final String answerIv;
  final Map<String, String> encryptedOfferKey;
  final Map<String, String> encryptedAnswerKey;
  final DateTime createdAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;
  final bool isOnHold;

  const CallModel({
    required this.callId,
    required this.callerUid,
    required this.calleeUid,
    required this.callerName,
    required this.calleeName,
    this.callerPhotoUrl = '',
    this.calleePhotoUrl = '',
    this.callerFcmToken = '',
    this.calleeFcmToken = '',
    required this.type,
    this.status = 'ringing',
    this.encryptedOffer = '',
    this.encryptedAnswer = '',
    this.offerIv = '',
    this.answerIv = '',
    this.encryptedOfferKey = const {},
    this.encryptedAnswerKey = const {},
    required this.createdAt,
    this.answeredAt,
    this.endedAt,
    this.isOnHold = false,
  });

  factory CallModel.fromMap(Map<String, dynamic> map) {
    return CallModel(
      callId: map['callId'] ?? '',
      callerUid: map['callerUid'] ?? '',
      calleeUid: map['calleeUid'] ?? '',
      callerName: map['callerName'] ?? '',
      calleeName: map['calleeName'] ?? '',
      callerPhotoUrl: map['callerPhotoUrl'] ?? '',
      calleePhotoUrl: map['calleePhotoUrl'] ?? '',
      callerFcmToken: map['callerFcmToken'] ?? '',
      calleeFcmToken: map['calleeFcmToken'] ?? '',
      type: map['type'] ?? 'audio',
      status: map['status'] ?? 'ringing',
      encryptedOffer: map['encryptedOffer'] ?? '',
      encryptedAnswer: map['encryptedAnswer'] ?? '',
      offerIv: map['offerIv'] ?? '',
      answerIv: map['answerIv'] ?? '',
      encryptedOfferKey:
          Map<String, String>.from(map['encryptedOfferKey'] ?? {}),
      encryptedAnswerKey:
          Map<String, String>.from(map['encryptedAnswerKey'] ?? {}),
      createdAt: map['createdAt'] is Timestamp
          ? (map['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      answeredAt: map['answeredAt'] is Timestamp
          ? (map['answeredAt'] as Timestamp).toDate()
          : null,
      endedAt: map['endedAt'] is Timestamp
          ? (map['endedAt'] as Timestamp).toDate()
          : null,
      isOnHold: map['isOnHold'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'callId': callId,
      'callerUid': callerUid,
      'calleeUid': calleeUid,
      'callerName': callerName,
      'calleeName': calleeName,
      'callerPhotoUrl': callerPhotoUrl,
      'calleePhotoUrl': calleePhotoUrl,
      'callerFcmToken': callerFcmToken,
      'calleeFcmToken': calleeFcmToken,
      'type': type,
      'status': status,
      'encryptedOffer': encryptedOffer,
      'encryptedAnswer': encryptedAnswer,
      'offerIv': offerIv,
      'answerIv': answerIv,
      'encryptedOfferKey': encryptedOfferKey,
      'encryptedAnswerKey': encryptedAnswerKey,
      'createdAt': Timestamp.fromDate(createdAt),
      'answeredAt':
          answeredAt != null ? Timestamp.fromDate(answeredAt!) : null,
      'endedAt': endedAt != null ? Timestamp.fromDate(endedAt!) : null,
      'isOnHold': isOnHold,
    };
  }

  CallModel copyWith({
    String? callId,
    String? callerUid,
    String? calleeUid,
    String? callerName,
    String? calleeName,
    String? callerPhotoUrl,
    String? calleePhotoUrl,
    String? callerFcmToken,
    String? calleeFcmToken,
    String? type,
    String? status,
    String? encryptedOffer,
    String? encryptedAnswer,
    String? offerIv,
    String? answerIv,
    Map<String, String>? encryptedOfferKey,
    Map<String, String>? encryptedAnswerKey,
    DateTime? createdAt,
    DateTime? answeredAt,
    DateTime? endedAt,
    bool? isOnHold,
  }) {
    return CallModel(
      callId: callId ?? this.callId,
      callerUid: callerUid ?? this.callerUid,
      calleeUid: calleeUid ?? this.calleeUid,
      callerName: callerName ?? this.callerName,
      calleeName: calleeName ?? this.calleeName,
      callerPhotoUrl: callerPhotoUrl ?? this.callerPhotoUrl,
      calleePhotoUrl: calleePhotoUrl ?? this.calleePhotoUrl,
      callerFcmToken: callerFcmToken ?? this.callerFcmToken,
      calleeFcmToken: calleeFcmToken ?? this.calleeFcmToken,
      type: type ?? this.type,
      status: status ?? this.status,
      encryptedOffer: encryptedOffer ?? this.encryptedOffer,
      encryptedAnswer: encryptedAnswer ?? this.encryptedAnswer,
      offerIv: offerIv ?? this.offerIv,
      answerIv: answerIv ?? this.answerIv,
      encryptedOfferKey: encryptedOfferKey ?? this.encryptedOfferKey,
      encryptedAnswerKey: encryptedAnswerKey ?? this.encryptedAnswerKey,
      createdAt: createdAt ?? this.createdAt,
      answeredAt: answeredAt ?? this.answeredAt,
      endedAt: endedAt ?? this.endedAt,
      isOnHold: isOnHold ?? this.isOnHold,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CallModel && other.callId == callId;
  }

  @override
  int get hashCode => callId.hashCode;

  @override
  String toString() {
    return 'CallModel('
        'callId: $callId, '
        'callerUid: $callerUid, '
        'calleeUid: $calleeUid, '
        'callerName: $callerName, '
        'calleeName: $calleeName, '
        'type: $type, '
        'status: $status, '
        'createdAt: $createdAt, '
        'answeredAt: $answeredAt, '
        'endedAt: $endedAt, '
        'isOnHold: $isOnHold)';
  }
}
