import 'package:cloud_firestore/cloud_firestore.dart';

class StoryModel {
  final String id;
  final String authorUid;
  final String authorUsername;
  final String authorPhotoUrl;
  final String authorDisplayName;
  final String text;
  final int gradientIndex;
  final DateTime createdAt;
  final List<String> viewers;
  final String? mediaUrl;
  final String mediaType; // "text" | "image" | "video"
  final String? captionText;

  const StoryModel({
    required this.id,
    required this.authorUid,
    required this.authorUsername,
    required this.authorPhotoUrl,
    required this.authorDisplayName,
    required this.text,
    required this.gradientIndex,
    required this.createdAt,
    required this.viewers,
    this.mediaUrl,
    this.mediaType = 'text',
    this.captionText,
  });

  factory StoryModel.fromMap(Map<String, dynamic> map) {
    return StoryModel(
      id: map['id'] as String? ?? '',
      authorUid: map['authorUid'] as String? ?? '',
      authorUsername: map['authorUsername'] as String? ?? '',
      authorPhotoUrl: map['authorPhotoUrl'] as String? ?? '',
      authorDisplayName: map['authorDisplayName'] as String? ?? '',
      text: map['text'] as String? ?? '',
      gradientIndex: map['gradientIndex'] as int? ?? 0,
      createdAt: map['createdAt'] is Timestamp
          ? (map['createdAt'] as Timestamp).toDate()
          : map['createdAt'] is DateTime
              ? map['createdAt'] as DateTime
              : DateTime.now(),
      viewers: map['viewers'] is List
          ? List<String>.from(map['viewers'] as List)
          : <String>[],
      mediaUrl: map['mediaUrl'] as String?,
      mediaType: map['mediaType'] as String? ?? 'text',
      captionText: map['captionText'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'authorUid': authorUid,
      'authorUsername': authorUsername,
      'authorPhotoUrl': authorPhotoUrl,
      'authorDisplayName': authorDisplayName,
      'text': text,
      'gradientIndex': gradientIndex,
      'createdAt': Timestamp.fromDate(createdAt),
      'viewers': viewers,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'captionText': captionText,
    };
  }

  bool get isExpired {
    return DateTime.now().difference(createdAt).inHours >= 24;
  }

  StoryModel copyWith({
    String? id,
    String? authorUid,
    String? authorUsername,
    String? authorPhotoUrl,
    String? authorDisplayName,
    String? text,
    int? gradientIndex,
    DateTime? createdAt,
    List<String>? viewers,
    String? mediaUrl,
    String? mediaType,
    String? captionText,
  }) {
    return StoryModel(
      id: id ?? this.id,
      authorUid: authorUid ?? this.authorUid,
      authorUsername: authorUsername ?? this.authorUsername,
      authorPhotoUrl: authorPhotoUrl ?? this.authorPhotoUrl,
      authorDisplayName: authorDisplayName ?? this.authorDisplayName,
      text: text ?? this.text,
      gradientIndex: gradientIndex ?? this.gradientIndex,
      createdAt: createdAt ?? this.createdAt,
      viewers: viewers ?? this.viewers,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaType: mediaType ?? this.mediaType,
      captionText: captionText ?? this.captionText,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoryModel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
