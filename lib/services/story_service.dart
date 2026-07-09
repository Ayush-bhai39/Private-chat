import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rxdart/rxdart.dart';
import 'package:secure_chat/models/story_model.dart';
import 'package:secure_chat/models/conversation_model.dart';
import 'package:secure_chat/services/user_service.dart';
import 'package:secure_chat/services/chat_service.dart';
import 'package:secure_chat/services/mock_config.dart';

class StoryService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;
  final UserService _userService = UserService();

  static final List<StoryModel> _mockStories = [];
  static final StreamController<List<StoryModel>> _mockStoryController = StreamController<List<StoryModel>>.broadcast();

  Future<void> createStory(String text, int gradientIndex, {String? mediaUrl, String mediaType = 'text', String? captionText}) async {
    final user = MockConfig.useMock ? null : _auth.currentUser;
    final uid = MockConfig.useMock ? "mock_uid_123" : (user?.uid ?? '');
    if (uid.isEmpty) throw Exception("User not logged in");

    final userData = await _userService.getUserData(uid);
    if (userData == null) throw Exception("User profile not found");

    final storyId = MockConfig.useMock ? DateTime.now().millisecondsSinceEpoch.toString() : _firestore.collection('stories').doc().id;

    final story = StoryModel(
      id: storyId,
      authorUid: uid,
      authorUsername: userData.username,
      authorPhotoUrl: userData.photoUrl,
      authorDisplayName: userData.displayName,
      text: text,
      gradientIndex: gradientIndex,
      createdAt: DateTime.now(),
      viewers: [],
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      captionText: captionText,
    );

    if (MockConfig.useMock) {
      _mockStories.insert(0, story);
      _mockStoryController.add(List.from(_mockStories));
      return;
    }

    await _firestore.collection('stories').doc(storyId).set(story.toMap());
  }

  Stream<List<StoryModel>> getStories() {
    final oneDayAgo = DateTime.now().subtract(const Duration(hours: 24));
    final chatStream = ChatService().getConversations();

    final storiesStream = MockConfig.useMock
        ? _mockStoryController.stream
        : _firestore
            .collection('stories')
            .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(oneDayAgo))
            .snapshots()
            .map((snapshot) {
            return snapshot.docs.map((doc) => StoryModel.fromMap(doc.data())).toList();
          });

    if (MockConfig.useMock) {
      Timer(const Duration(milliseconds: 100), () {
        _mockStoryController.add(List.from(_mockStories));
      });
    }

    return Rx.combineLatest2<List<StoryModel>, List<ConversationModel>, List<StoryModel>>(
      storiesStream,
      chatStream,
      (stories, conversations) {
        final currentUid = MockConfig.useMock ? "mock_uid_123" : (_auth.currentUser?.uid ?? '');
        final contactedUids = conversations.map((c) => c.otherUser.uid).toSet();

        final filtered = stories.where((story) {
          return story.authorUid == currentUid || contactedUids.contains(story.authorUid);
        }).toList();

        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return filtered;
      },
    );
  }

  Future<void> markAsViewed(String storyId) async {
    final user = MockConfig.useMock ? null : _auth.currentUser;
    final uid = MockConfig.useMock ? "mock_uid_123" : (user?.uid ?? '');
    if (uid.isEmpty) return;

    if (MockConfig.useMock) {
      final index = _mockStories.indexWhere((s) => s.id == storyId);
      if (index != -1) {
        final story = _mockStories[index];
        if (!story.viewers.contains(uid)) {
          final updatedViewers = List<String>.from(story.viewers)..add(uid);
          _mockStories[index] = story.copyWith(viewers: updatedViewers);
          _mockStoryController.add(List.from(_mockStories));
        }
      }
      return;
    }

    await _firestore.collection('stories').doc(storyId).update({
      'viewers': FieldValue.arrayUnion([uid])
    });
  }

  Future<void> deleteStory(String storyId) async {
    if (MockConfig.useMock) {
      _mockStories.removeWhere((s) => s.id == storyId);
      _mockStoryController.add(List.from(_mockStories));
      return;
    }
    await _firestore.collection('stories').doc(storyId).delete();
  }
}
