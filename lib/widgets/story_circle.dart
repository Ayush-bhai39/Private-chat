import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:secure_chat/config/theme.dart';
import 'package:secure_chat/models/story_model.dart';
import 'package:secure_chat/models/user_model.dart';

class StoryCircle extends StatelessWidget {
  final List<StoryModel> stories;

  const StoryCircle({
    super.key,
    required this.stories,
  });

  @override
  Widget build(BuildContext context) {
    if (stories.isEmpty) return const SizedBox.shrink();
    final story = stories.first;
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final allSeen = currentUid != null && stories.every((s) => s.viewers.contains(currentUid));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: allSeen ? null : AppTheme.storyRingGradient,
            color: allSeen ? Colors.white24 : null,
          ),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.background,
            ),
            child: CircleAvatar(
              radius: 24,
              backgroundColor: AppTheme.surface,
              backgroundImage: UserModel.getAvatarImageProvider(story.authorPhotoUrl),
              child: story.authorPhotoUrl.isEmpty
                  ? Text(
                      story.authorDisplayName.isNotEmpty
                          ? story.authorDisplayName[0].toUpperCase()
                          : 'U',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 64,
          child: Text(
            story.authorDisplayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
