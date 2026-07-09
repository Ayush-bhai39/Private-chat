import 'package:cloud_firestore/cloud_firestore.dart';

class MessageModel {
  final String id;
  final String senderUid;
  final String encryptedMessage;
  final String encryptedKey;
  final String iv;
  final DateTime timestamp;
  final String? decryptedText;
  final bool isEdited;
  final bool isDeleted;
  final List<String> deletedForUsers;
  final Map<String, String> reactions;
  final String? mediaUrl;
  final String? mediaType;
  final String? fallbackContent;
  final String? repliedMessageId;
  final String? repliedMessageSenderUid;
  final String? repliedMessageSenderName;
  final String? encryptedRepliedText;
  
  // Status fields for ticks ('sent', 'delivered', 'seen')
  final String status;
  // Local transient state for pending uploads (not saved to Firestore)
  final bool hasPendingWrites;

  const MessageModel({
    required this.id,
    required this.senderUid,
    required this.encryptedMessage,
    required this.encryptedKey,
    required this.iv,
    required this.timestamp,
    this.decryptedText,
    this.isEdited = false,
    this.isDeleted = false,
    this.deletedForUsers = const [],
    this.reactions = const {},
    this.mediaUrl,
    this.mediaType,
    this.fallbackContent,
    this.repliedMessageId,
    this.repliedMessageSenderUid,
    this.repliedMessageSenderName,
    this.encryptedRepliedText,
    this.status = 'sent',
    this.hasPendingWrites = false,
  });

  factory MessageModel.fromMap(Map<String, dynamic> map) {
    return MessageModel(
      id: map['id'] as String? ?? '',
      senderUid: map['senderUid'] as String? ?? '',
      encryptedMessage: map['encryptedMessage'] as String? ?? '',
      encryptedKey: map['encryptedKey'] as String? ?? '',
      iv: map['iv'] as String? ?? '',
      timestamp: map['timestamp'] is Timestamp
          ? (map['timestamp'] as Timestamp).toDate()
          : map['timestamp'] is DateTime
              ? map['timestamp'] as DateTime
              : DateTime.now(),
      isEdited: map['isEdited'] as bool? ?? false,
      isDeleted: map['isDeleted'] as bool? ?? false,
      deletedForUsers: List<String>.from(map['deletedForUsers'] ?? []),
      reactions: Map<String, String>.from(map['reactions'] ?? {}),
      mediaUrl: map['mediaUrl'] as String?,
      mediaType: map['mediaType'] as String?,
      fallbackContent: map['fallbackContent'] as String?,
      repliedMessageId: map['repliedMessageId'] as String?,
      repliedMessageSenderUid: map['repliedMessageSenderUid'] as String?,
      repliedMessageSenderName: map['repliedMessageSenderName'] as String?,
      encryptedRepliedText: map['encryptedRepliedText'] as String?,
      status: map['status'] as String? ?? 'sent',
      hasPendingWrites: false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderUid': senderUid,
      'encryptedMessage': encryptedMessage,
      'encryptedKey': encryptedKey,
      'iv': iv,
      'timestamp': Timestamp.fromDate(timestamp),
      'isEdited': isEdited,
      'isDeleted': isDeleted,
      'deletedForUsers': deletedForUsers,
      'reactions': reactions,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'fallbackContent': fallbackContent,
      'repliedMessageId': repliedMessageId,
      'repliedMessageSenderUid': repliedMessageSenderUid,
      'repliedMessageSenderName': repliedMessageSenderName,
      'encryptedRepliedText': encryptedRepliedText,
      'status': status,
    };
  }

  MessageModel copyWith({
    String? id,
    String? senderUid,
    String? encryptedMessage,
    String? encryptedKey,
    String? iv,
    DateTime? timestamp,
    String? decryptedText,
    bool? isEdited,
    bool? isDeleted,
    List<String>? deletedForUsers,
    Map<String, String>? reactions,
    String? mediaUrl,
    String? mediaType,
    String? fallbackContent,
    String? repliedMessageId,
    String? repliedMessageSenderUid,
    String? repliedMessageSenderName,
    String? encryptedRepliedText,
    String? status,
    bool? hasPendingWrites,
  }) {
    return MessageModel(
      id: id ?? this.id,
      senderUid: senderUid ?? this.senderUid,
      encryptedMessage: encryptedMessage ?? this.encryptedMessage,
      encryptedKey: encryptedKey ?? this.encryptedKey,
      iv: iv ?? this.iv,
      timestamp: timestamp ?? this.timestamp,
      decryptedText: decryptedText ?? this.decryptedText,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedForUsers: deletedForUsers ?? this.deletedForUsers,
      reactions: reactions ?? this.reactions,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaType: mediaType ?? this.mediaType,
      fallbackContent: fallbackContent ?? this.fallbackContent,
      repliedMessageId: repliedMessageId ?? this.repliedMessageId,
      repliedMessageSenderUid: repliedMessageSenderUid ?? this.repliedMessageSenderUid,
      repliedMessageSenderName: repliedMessageSenderName ?? this.repliedMessageSenderName,
      encryptedRepliedText: encryptedRepliedText ?? this.encryptedRepliedText,
      status: status ?? this.status,
      hasPendingWrites: hasPendingWrites ?? this.hasPendingWrites,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageModel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'MessageModel(id: $id, senderUid: $senderUid, '
        'timestamp: $timestamp, status: $status, isEdited: $isEdited, isDeleted: $isDeleted)';
  }
}
