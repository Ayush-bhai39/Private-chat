import 'package:cloud_firestore/cloud_firestore.dart';

class NoteModel {
  final String uid;
  final String text;
  final DateTime createdAt;
  final String displayName;
  final String photoUrl;

  const NoteModel({
    required this.uid,
    required this.text,
    required this.createdAt,
    required this.displayName,
    required this.photoUrl,
  });

  factory NoteModel.fromMap(Map<String, dynamic> map) {
    return NoteModel(
      uid: map['uid'] as String? ?? '',
      text: map['text'] as String? ?? '',
      createdAt: map['createdAt'] is Timestamp
          ? (map['createdAt'] as Timestamp).toDate()
          : map['createdAt'] is DateTime
              ? map['createdAt'] as DateTime
              : DateTime.now(),
      displayName: map['displayName'] as String? ?? '',
      photoUrl: map['photoUrl'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'text': text,
      'createdAt': Timestamp.fromDate(createdAt),
      'displayName': displayName,
      'photoUrl': photoUrl,
    };
  }

  bool get isExpired {
    return DateTime.now().difference(createdAt).inHours >= 24;
  }

  NoteModel copyWith({
    String? uid,
    String? text,
    DateTime? createdAt,
    String? displayName,
    String? photoUrl,
  }) {
    return NoteModel(
      uid: uid ?? this.uid,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteModel &&
          runtimeType == other.runtimeType &&
          uid == other.uid;

  @override
  int get hashCode => uid.hashCode;
}
