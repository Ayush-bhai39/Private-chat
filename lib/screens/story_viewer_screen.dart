import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:secure_chat/config/theme.dart';
import 'package:secure_chat/models/story_model.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:secure_chat/services/mock_config.dart';
import 'package:secure_chat/services/story_service.dart';


import 'package:secure_chat/models/user_model.dart';
import 'package:secure_chat/services/user_service.dart';


class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({super.key});

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  final _storyService = StoryService();
  final _userService = UserService();

  List<StoryModel> _stories = [];
  int _currentIndex = 0;

  double _progress = 0.0;
  late final AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    _progressController.addListener(() {
      setState(() => _progress = _progressController.value);
    });
    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _nextStory();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stories.isEmpty) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null) {
        _stories = args['stories'] as List<StoryModel>;
        _currentIndex = args['initialIndex'] as int? ?? 0;
        _startTimer();
      } else {
        Navigator.of(context).pop();
      }
    }
  }

  void _startTimer() {
    _progressController.reset();
    _progressController.forward();
    _markStoryAsViewed();
  }

  void _markStoryAsViewed() {
    if (_currentIndex < _stories.length) {
      _storyService.markAsViewed(_stories[_currentIndex].id);
    }
  }

  void _nextStory() {
    if (_currentIndex < _stories.length - 1) {
      setState(() {
        _currentIndex++;
        _startTimer();
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  void _previousStory() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _startTimer();
      });
    } else {
      _progressController.reset();
      _progressController.forward();
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  Future<void> _deleteStory(StoryModel story) async {
    _progressController.stop(); // Pause timer

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Story?'),
        content: const Text('This will permanently delete this story for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              minimumSize: const Size(80, 36),
            ),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _storyService.deleteStory(story.id);
        
        setState(() {
          _stories.removeAt(_currentIndex);
        });

        if (_stories.isEmpty) {
          if (mounted) {
            Navigator.of(context).pop();
          }
        } else {
          if (_currentIndex >= _stories.length) {
            _currentIndex = _stories.length - 1;
          }
          _startTimer();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete story: $e')),
          );
          _progressController.forward(); // Resume
        }
      }
    } else {
      _progressController.forward(); // Resume
    }
  }

  Widget _buildStoryContent(StoryModel story) {
    if (story.mediaType == 'image' && story.mediaUrl != null) {
      if (story.mediaUrl!.startsWith('data:image')) {
        try {
          final base64String = story.mediaUrl!.split(',').last.replaceAll(RegExp(r'\s+'), '');
          final bytes = base64Decode(base64String);
          return Image.memory(
            bytes,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, error, stackTrace) {
              print("Image.memory asynchronous decode error: $error");
              return const Center(
                child: Icon(Icons.broken_image_rounded, size: 64, color: Colors.white),
              );
            },
          );
        } catch (e) {
          print("Base64 decode synchronous exception: $e");
          return const Center(
            child: Icon(Icons.broken_image_rounded, size: 64, color: Colors.white),
          );
        }
      }

      // Check if it is a local path safely without throwing exceptions on web URLs
      if (!story.mediaUrl!.startsWith('http://') && !story.mediaUrl!.startsWith('https://')) {
        try {
          final file = File(story.mediaUrl!);
          if (file.existsSync()) {
            return Image.file(
              file,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            );
          }
        } catch (_) {}
      }

      return CachedNetworkImage(
        imageUrl: story.mediaUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder: (context, url) => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
        errorWidget: (context, url, error) => const Center(
          child: Icon(Icons.broken_image_rounded, size: 64, color: Colors.white),
        ),
      );
    }

    // Text story with gradient background
    final gradient = AppTheme.storyGradients[story.gradientIndex % AppTheme.storyGradients.length];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            story.text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Colors.black26,
                  offset: Offset(0, 4),
                  blurRadius: 10,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_stories.isEmpty) return const Scaffold();

    final story = _stories[_currentIndex];
    final String? caption = story.captionText ?? (story.text.isNotEmpty && story.mediaType == 'image' ? story.text : null);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (details) {
          final width = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < width / 3) {
            _previousStory();
          } else {
            _nextStory();
          }
        },
        child: Stack(
          children: [
            // Story background & media
            Positioned.fill(
              child: _buildStoryContent(story),
            ),

            // Image caption overlay (if image has text caption)
            if (story.mediaType == 'image' && caption != null && caption.isNotEmpty)
              Positioned(
                bottom: 84,
                left: 24,
                right: 24,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(160),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.15),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    caption,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

            // Header indicators & User Profile Info
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black54, Colors.transparent],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                padding: const EdgeInsets.only(top: 12),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Progress Bar indicators
                        Row(
                          children: List.generate(_stories.length, (index) {
                            double val = 0.0;
                            if (index < _currentIndex) val = 1.0;
                            if (index == _currentIndex) val = _progress;

                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(1),
                                  child: LinearProgressIndicator(
                                    value: val,
                                    backgroundColor: Colors.white.withOpacity(0.3),
                                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                    minHeight: 2,
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 12),

                        // User Profile Info
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: Colors.white24,
                              backgroundImage: story.authorPhotoUrl.isNotEmpty
                                  ? NetworkImage(story.authorPhotoUrl)
                                  : null,
                              child: story.authorPhotoUrl.isEmpty
                                  ? const Icon(Icons.person, size: 18, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    story.authorDisplayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    '@${story.authorUsername}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            if (story.authorUid == (MockConfig.useMock ? "mock_uid_123" : (FirebaseAuth.instance.currentUser?.uid ?? '')))
                              IconButton(
                                onPressed: () => _deleteStory(story),
                                icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.error),
                              ),
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close_rounded, color: Colors.white),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            
            // Story Viewers Counter Pill (Only visible to the author of the story)
            if (story.authorUid == (MockConfig.useMock ? "mock_uid_123" : (FirebaseAuth.instance.currentUser?.uid ?? '')))
              Positioned(
                bottom: 30,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () => _showViewersSheet(story),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.15),
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.visibility_outlined, color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            '${story.viewers.length} views',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showViewersSheet(StoryModel story) {
    _progressController.stop(); // Pause story progress timer

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.surface.withAlpha(245),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: AppTheme.surfaceLight, width: 0.5),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textSecondary.withAlpha(80),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Story Views',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '${story.viewers.length} views',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          color: AppTheme.accentPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: story.viewers.isEmpty
                      ? Container(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: const Center(
                            child: Text(
                              'No views yet',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        )
                      : FutureBuilder<List<UserModel>>(
                          future: _loadViewers(story.viewers),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            final users = snapshot.data ?? [];
                            if (users.isEmpty) {
                              return Container(
                                padding: const EdgeInsets.symmetric(vertical: 40),
                                child: const Center(
                                  child: Text(
                                    'No views yet',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                              );
                            }
                            return ListView.builder(
                              shrinkWrap: true,
                              itemCount: users.length,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              itemBuilder: (context, index) {
                                final user = users[index];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.white24,
                                    backgroundImage: user.avatarImage,
                                    child: user.photoUrl.isEmpty
                                        ? const Icon(Icons.person, color: Colors.white)
                                        : null,
                                  ),
                                  title: Text(
                                    user.displayName,
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '@${user.username}',
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    ).then((value) {
      if (mounted) {
        _progressController.forward(); // Resume progress timer when sheet closes
      }
    });
  }

  Future<List<UserModel>> _loadViewers(List<String> uids) async {
    final list = <UserModel>[];
    for (final uid in uids) {
      final user = await _userService.getUserData(uid);
      if (user != null) {
        list.add(user);
      }
    }
    return list;
  }
}
