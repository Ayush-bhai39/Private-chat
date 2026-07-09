import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final String photoUrl;
  final String username;
  final String publicKey;
  final DateTime createdAt;
  final bool isPrivate;
  final List<String> followers;
  final List<String> following;
  final List<String> followRequests;
  final String fcmToken;

  const UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.photoUrl,
    required this.username,
    required this.publicKey,
    required this.createdAt,
    this.isPrivate = false,
    this.followers = const [],
    this.following = const [],
    this.followRequests = const [],
    this.fcmToken = '',
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] as String? ?? '',
      email: map['email'] as String? ?? '',
      displayName: map['displayName'] as String? ?? '',
      photoUrl: map['photoUrl'] as String? ?? '',
      username: map['username'] as String? ?? '',
      publicKey: map['publicKey'] as String? ?? '',
      createdAt: map['createdAt'] is Timestamp
          ? (map['createdAt'] as Timestamp).toDate()
          : map['createdAt'] is DateTime
              ? map['createdAt'] as DateTime
              : DateTime.now(),
      isPrivate: map['isPrivate'] as bool? ?? false,
      followers: List<String>.from(map['followers'] ?? []),
      following: List<String>.from(map['following'] ?? []),
      followRequests: List<String>.from(map['followRequests'] ?? []),
      fcmToken: map['fcmToken'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'username': username,
      'publicKey': publicKey,
      'createdAt': Timestamp.fromDate(createdAt),
      'isPrivate': isPrivate,
      'followers': followers,
      'following': following,
      'followRequests': followRequests,
      'fcmToken': fcmToken,
    };
  }

  UserModel copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? photoUrl,
    String? username,
    String? publicKey,
    DateTime? createdAt,
    bool? isPrivate,
    List<String>? followers,
    List<String>? following,
    List<String>? followRequests,
    String? fcmToken,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      username: username ?? this.username,
      publicKey: publicKey ?? this.publicKey,
      createdAt: createdAt ?? this.createdAt,
      isPrivate: isPrivate ?? this.isPrivate,
      followers: followers ?? this.followers,
      following: following ?? this.following,
      followRequests: followRequests ?? this.followRequests,
      fcmToken: fcmToken ?? this.fcmToken,
    );
  }

  ImageProvider? get avatarImage => getAvatarImageProvider(photoUrl);

  static final Map<String, ImageProvider> _avatarCache = {};

  static ImageProvider? getAvatarImageProvider(String? url) {
    if (url == null || url.isEmpty) return null;
    if (_avatarCache.containsKey(url)) {
      return _avatarCache[url];
    }
    
    ImageProvider? provider;
    if (url.startsWith('data:image') || url.startsWith('data:application') || !url.startsWith('http')) {
      try {
        final base64String = url.contains(',') ? url.split(',').last : url;
        provider = MemoryImage(base64Decode(base64String));
      } catch (e) {
        return null;
      }
    } else {
      provider = NetworkImage(url);
    }
    
    _avatarCache[url] = provider;
    return provider;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserModel &&
          runtimeType == other.runtimeType &&
          uid == other.uid;

  @override
  int get hashCode => uid.hashCode;

  @override
  String toString() {
    return 'UserModel(uid: $uid, email: $email, displayName: $displayName, '
        'username: $username, isPrivate: $isPrivate)';
  }
}
