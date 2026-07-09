import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:secure_chat/config/theme.dart';
import 'package:secure_chat/models/user_model.dart';
import 'package:secure_chat/models/conversation_model.dart';
import 'package:secure_chat/models/story_model.dart';
import 'package:secure_chat/models/note_model.dart';
import 'package:secure_chat/services/auth_service.dart';
import 'package:secure_chat/services/chat_service.dart';
import 'package:secure_chat/services/story_service.dart';
import 'package:secure_chat/services/note_service.dart';
import 'package:secure_chat/services/user_service.dart';
import 'package:secure_chat/services/storage_service.dart';
import 'package:secure_chat/services/update_service.dart';
import 'package:secure_chat/services/notification_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:secure_chat/widgets/story_circle.dart';
import 'package:secure_chat/widgets/note_circle.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:secure_chat/widgets/conversation_tile.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  final _chatService = ChatService();
  final _storyService = StoryService();
  final _noteService = NoteService();
  final _userService = UserService();
  final _storageService = StorageService();

  late final ScrollController _scrollController;
  final _scrollOffsetNotifier = ValueNotifier<double>(0.0);
  late final AnimationController _fabController;
  late final Animation<double> _fabScale;

  UserModel? _currentUser;
  bool _isStoryLoading = false;
  bool _isNoteLoading = false;
  bool _isUpdateAvailable = false;
  Map<String, dynamic>? _updateInfo;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(() {
      _scrollOffsetNotifier.value = _scrollController.offset;
    });
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
    _fabScale = CurvedAnimation(
      parent: _fabController,
      curve: Curves.elasticOut,
    );
    _loadCurrentUser();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdates();
    });
  }

  Future<void> _checkUpdates() async {
    final info = await UpdateService().getUpdateInfo();
    if (info != null) {
      if (mounted) {
        setState(() {
          _isUpdateAvailable = true;
          _updateInfo = info;
        });
        UpdateService().showUpdateDialog(
          context,
          info['versionName'] ?? '1.0.0',
          info['downloadUrl'] ?? '',
          info['forceUpdate'] ?? false,
        );
      }
      UpdateService().showNativeUpdateNotification(info['versionName'] ?? '1.0.0', info['downloadUrl'] ?? '');
    }
  }

  Future<void> _loadCurrentUser() async {
    final user = _authService.currentUser;
    if (user != null) {
      final userData = await _userService.getUserData(user.uid);
      if (mounted) setState(() => _currentUser = userData);
      
      // Initialize and start listening for incoming E2EE messages
      try {
        await NotificationService.instance.init();
        await NotificationService.instance.updateFcmToken();
        NotificationService.instance.startListening(user.uid);
      } catch (e) {
        print("Error starting notifications: $e");
      }
    }
  }

  Future<void> _handleSignOut() async {
    await _authService.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/welcome');
    }
  }

  Future<void> _shareAppLink() async {
    final uri = Uri.parse('https://github.com/Ayush-bhai39/Private-chat/raw/main/app-release.apk');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showProfileMenu() {
    showMenu(
      context: context,
      position: const RelativeRect.fromLTRB(100, 80, 0, 0),
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem(
          onTap: _shareAppLink,
          child: Row(
            children: [
              const Icon(Icons.share_rounded, size: 20, color: AppTheme.textSecondary),
              const SizedBox(width: 12),
              Text(
                'Share App',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          onTap: _handleSignOut,
          child: Row(
            children: [
              const Icon(Icons.logout_rounded, size: 20, color: AppTheme.textSecondary),
              const SizedBox(width: 12),
              Text(
                'Sign Out',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _createNewStory() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.surface.withAlpha(240),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: AppTheme.surfaceLight, width: 1),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.textSecondary.withAlpha(77),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Create Story',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStoryOption(
                        icon: Icons.camera_alt_rounded,
                        label: 'Camera',
                        gradient: [const Color(0xFF667eea), const Color(0xFF764ba2)],
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.pushNamed(context, '/story-editor', arguments: {'source': 'camera'});
                        },
                      ),
                      _buildStoryOption(
                        icon: Icons.photo_library_rounded,
                        label: 'Gallery',
                        gradient: [const Color(0xFF11998e), const Color(0xFF38ef7d)],
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.pushNamed(context, '/story-editor', arguments: {'source': 'gallery'});
                        },
                      ),
                      _buildStoryOption(
                        icon: Icons.text_fields_rounded,
                        label: 'Text',
                        gradient: [const Color(0xFFf857a6), const Color(0xFFff5858)],
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.pushNamed(context, '/story-editor', arguments: {'source': 'text'});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStoryOption({
    required IconData icon,
    required String label,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: gradient[0].withAlpha(80),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateNoteDialog(NoteModel? currentNote) {
    final controller = TextEditingController(text: currentNote?.text ?? '');

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'NoteDialog',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) => const SizedBox.shrink(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final scale = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
        final fade = CurvedAnimation(parent: animation, curve: Curves.easeIn);

        return FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: scale,
            child: AlertDialog(
              backgroundColor: AppTheme.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [AppTheme.accentPrimary, AppTheme.accentSecondary],
                    ).createShader(bounds),
                    child: const Text(
                      'Share a Thought',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notes appear at the top of chats for 24 hours.',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: AppTheme.textSecondary.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      controller: controller,
                      maxLength: 60,
                      maxLines: 2,
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 15),
                      decoration: const InputDecoration(
                        hintText: "What's on your mind?...",
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                        counterStyle: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                if (currentNote != null)
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      try {
                        setState(() => _isNoteLoading = true);
                        await _noteService.deleteNote();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Note deleted')),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red.shade800),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _isNoteLoading = false);
                      }
                    },
                    child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final text = controller.text.trim();
                    if (text.isEmpty) return;
                    Navigator.pop(context);
                    try {
                      setState(() => _isNoteLoading = true);
                      await _noteService.createOrUpdateNote(text);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Note shared successfully!')),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error sharing note: $e'), backgroundColor: Colors.red.shade800),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _isNoteLoading = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentPrimary,
                    minimumSize: const Size(80, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: const Text('Share', style: TextStyle(fontSize: 14)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    NotificationService.instance.stopListening();
    _fabController.dispose();
    _scrollController.dispose();
    _scrollOffsetNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _loadCurrentUser,
            color: AppTheme.accentPrimary,
            backgroundColor: AppTheme.surface,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // 2. Large Scrolling Header (with Large Title, notifications, and Account Avatar)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 16,
                      left: 16,
                      right: 16,
                      bottom: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [AppTheme.accentPrimary, AppTheme.accentSecondary],
                          ).createShader(bounds),
                          child: const Text(
                            'Secret Chat',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            if (_isUpdateAvailable)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: TextButton(
                                  onPressed: () async {
                                    final url = _updateInfo?['downloadUrl'] as String? ?? 'https://github.com/Ayush-bhai39/Private-chat/raw/main/app-release.apk';
                                    final uri = Uri.parse(url);
                                    if (uri.scheme == 'http' || uri.scheme == 'https') {
                                      try {
                                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                                      } catch (e) {
                                        print("Error launching update URL: $e");
                                      }
                                    } else {
                                      print("Blocked launching insecure URL: $url");
                                    }
                                  },
                                  child: const Text(
                                    'Update Available',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      color: Colors.yellow,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            GestureDetector(
                              onTap: _showNotificationsSheet,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 12),
                                    child: Icon(
                                      Icons.notifications_outlined,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                  if ((_currentUser?.followRequests.isNotEmpty == true) ||
                                      (_currentUser != null && _currentUser!.followers.any((f) => !_currentUser!.following.contains(f))))
                                    Positioned(
                                      right: 12,
                                      top: 0,
                                      child: Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: AppTheme.accentPrimary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () async {
                                await Navigator.pushNamed(context, '/account');
                                _loadCurrentUser();
                              },
                              child: CircleAvatar(
                                radius: 18,
                                backgroundColor: AppTheme.surface,
                                backgroundImage: _currentUser?.avatarImage,
                                child: _currentUser?.photoUrl == null ||
                                        _currentUser!.photoUrl.isEmpty
                                    ? const Icon(Icons.person, size: 20, color: AppTheme.textSecondary)
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // 3. Stories section
                SliverToBoxAdapter(
                  child: _buildStoriesSection(),
                ),

                // 4. Notes section
                SliverToBoxAdapter(
                  child: _buildNotesSection(),
                ),

                // 5. Divider
                SliverToBoxAdapter(
                  child: Divider(
                    height: 1,
                    thickness: 0.5,
                    color: AppTheme.surfaceLight.withOpacity(0.3),
                  ),
                ),

                // 6. Conversations list sliver
                _buildConversationsSliver(),
              ],
            ),
          ),

          // 7. Pinned frosted glass app bar overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: _scrollOffsetNotifier,
              builder: (context, offset, child) {
                // Calculate opacity based on scroll offset (fade in between offset 15 and 45)
                final double opacity = ((offset - 15) / 30).clamp(0.0, 1.0);
                
                return IgnorePointer(
                  ignoring: true, // Let all taps pass through to the header buttons underneath
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10 * opacity, sigmaY: 10 * opacity),
                      child: Container(
                        height: MediaQuery.of(context).padding.top + 56,
                        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
                        decoration: BoxDecoration(
                          color: AppTheme.background.withOpacity(0.7 * opacity),
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.white.withOpacity(0.05 * opacity),
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: NavigationToolbar(
                          centerMiddle: true,
                          middle: Opacity(
                            opacity: opacity,
                            child: ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [AppTheme.accentPrimary, AppTheme.accentSecondary],
                              ).createShader(bounds),
                              child: const Text(
                                'Secret Chat',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isStoryLoading || _isNoteLoading)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: AppTheme.accentPrimary),
                    const SizedBox(height: 16),
                    Text(
                      _isStoryLoading ? 'Sharing your story...' : 'Updating your note...',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: ScaleTransition(
        scale: _fabScale,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [AppTheme.accentPrimary, AppTheme.accentSecondary],
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentPrimary.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: FloatingActionButton(
            onPressed: () => Navigator.of(context).pushNamed('/new-chat'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            hoverElevation: 0,
            focusElevation: 0,
            highlightElevation: 0,
            child: const Icon(Icons.add, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }

  Widget _buildStoriesSection() {
    return SizedBox(
      height: 100,
      child: StreamBuilder<List<StoryModel>>(
        stream: _storyService.getStories(),
        builder: (context, snapshot) {
          final stories = snapshot.data ?? [];
          
          // Pre-cache story media in background for instant load
          if (stories.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                for (final story in stories) {
                  if (story.mediaType == 'image' && story.mediaUrl != null) {
                    final url = story.mediaUrl!;
                    if (url.startsWith('http')) {
                      precacheImage(CachedNetworkImageProvider(url), context);
                    }
                  }
                }
              }
            });
          }

          final grouped = <String, List<StoryModel>>{};
          for (final story in stories) {
            grouped.putIfAbsent(story.authorUid, () => []).add(story);
          }

          final currentUid = _authService.currentUser?.uid;
          final hasOwnStory =
              currentUid != null && grouped.containsKey(currentUid);

          return ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              // Own story
              GestureDetector(
                onTap: () {
                  if (hasOwnStory) {
                    Navigator.of(context).pushNamed(
                      '/story-viewer',
                      arguments: {
                        'stories': grouped[currentUid]!,
                        'initialIndex': 0,
                      },
                    );
                  } else {
                    _createNewStory();
                  }
                },
                onLongPress: _createNewStory,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        children: [
                          Container(
                            padding: hasOwnStory ? const EdgeInsets.all(2.5) : EdgeInsets.zero,
                            decoration: hasOwnStory
                                ? BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: (currentUid != null &&
                                            grouped[currentUid] != null &&
                                            grouped[currentUid]!.every((s) => s.viewers.contains(currentUid)))
                                        ? null
                                        : AppTheme.storyRingGradient,
                                    color: (currentUid != null &&
                                            grouped[currentUid] != null &&
                                            grouped[currentUid]!.every((s) => s.viewers.contains(currentUid)))
                                        ? Colors.white24
                                        : null,
                                  )
                                : null,
                            child: Container(
                              padding: hasOwnStory ? const EdgeInsets.all(2) : EdgeInsets.zero,
                              decoration: hasOwnStory
                                  ? const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppTheme.background,
                                    )
                                  : null,
                              child: CircleAvatar(
                                radius: 24,
                                backgroundColor: AppTheme.surface,
                                backgroundImage: _currentUser?.avatarImage,
                                child: _currentUser?.photoUrl == null ||
                                        _currentUser!.photoUrl.isEmpty
                                    ? const Icon(Icons.person,
                                        size: 22, color: AppTheme.textSecondary)
                                    : null,
                              ),
                            ),
                          ),
                          if (!hasOwnStory)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: AppTheme.accentPrimary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppTheme.background,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.add,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const SizedBox(
                        width: 64,
                        child: Text(
                          'Your story',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Other stories
              ...grouped.entries
                  .where((e) => e.key != currentUid)
                  .map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(context).pushNamed(
                        '/story-viewer',
                        arguments: {
                          'stories': entry.value,
                          'initialIndex': 0,
                        },
                      );
                    },
                    child: StoryCircle(
                      stories: entry.value,
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _buildNotesSection() {
    return StreamBuilder<List<NoteModel>>(
      stream: _noteService.getNotes(),
      builder: (context, snapshot) {
        final notes = snapshot.data ?? [];
        
        return StreamBuilder<NoteModel?>(
          stream: _noteService.getMyNote(),
          builder: (context, myNoteSnapshot) {
            final myNote = myNoteSnapshot.data;
 
            return SizedBox(
              height: 124,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                children: [
                  // Own note
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: NoteCircle(
                      note: myNote,
                      displayName: 'Your note',
                      isAddNote: myNote == null,
                      profilePhotoUrl: _currentUser?.photoUrl,
                      onTap: () => _showCreateNoteDialog(myNote),
                    ),
                  ),
                  // Other notes
                  ...notes.map((note) => Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: NoteCircle(note: note),
                      )),
                ],
              ),
            );
          }
        );
      },
    );
  }

  Widget _buildConversationsSliver() {
    return StreamBuilder<List<ConversationModel>>(
      stream: _chatService.getConversations(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SliverToBoxAdapter(
            child: SizedBox(
              height: 200,
              child: Center(
                child: CircularProgressIndicator(
                  color: AppTheme.accentPrimary,
                  strokeWidth: 2,
                ),
              ),
            ),
          );
        }

        final conversations = snapshot.data ?? [];

        if (conversations.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 64,
                    color: AppTheme.textSecondary.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No conversations yet',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap + to start chatting',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      color: AppTheme.textSecondary.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final conversation = conversations[index];
              return ConversationTile(
                conversation: conversation,
                onTap: () {
                  Navigator.of(context).pushNamed(
                    '/chat',
                    arguments: conversation.otherUser,
                  );
                },
              );
            },
            childCount: conversations.length,
          ),
        );
      },
    );
  }

  Future<Map<String, List<UserModel>>> _loadNotificationLists() async {
    final currentUid = _authService.currentUser?.uid;
    if (currentUid == null) return {'requests': [], 'followers': []};

    final latestUser = await _userService.getUserData(currentUid);
    if (latestUser != null && mounted) {
      setState(() {
        _currentUser = latestUser;
      });
    }

    final reqs = await _userService.getFollowRequests(currentUid);
    
    final followersToFollowBack = <UserModel>[];
    if (latestUser != null) {
      for (final fUid in latestUser.followers) {
        if (!latestUser.following.contains(fUid)) {
          final u = await _userService.getUserData(fUid);
          if (u != null) {
            followersToFollowBack.add(u);
          }
        }
      }
    }

    return {
      'requests': reqs,
      'followers': followersToFollowBack,
    };
  }

  void _showNotificationsSheet() {
    final currentUid = _authService.currentUser?.uid;
    if (currentUid == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) {
        List<UserModel>? requests;
        List<UserModel>? followers;
        bool isLoading = true;
        String? loadingUserId;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            if (isLoading && requests == null) {
              _loadNotificationLists().then((data) {
                setSheetState(() {
                  requests = data['requests'];
                  followers = data['followers'];
                  isLoading = false;
                });
              });
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Notifications',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: AppTheme.accentPrimary,
                            ),
                          )
                        : (requests!.isEmpty && followers!.isEmpty)
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.notifications_none_rounded,
                                      size: 48,
                                      color: AppTheme.textSecondary.withOpacity(0.3),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'All caught up! ✨',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 14,
                                        color: AppTheme.textSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView(
                                children: [
                                  if (requests!.isNotEmpty) ...[
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 8),
                                      child: Text(
                                        'FOLLOW REQUESTS',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.accentPrimary,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                    ),
                                    ...requests!.map((user) {
                                      final isUserLoading = loadingUserId == user.uid;
                                      return ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: CircleAvatar(
                                          radius: 20,
                                          backgroundColor: AppTheme.surface,
                                          backgroundImage: user.avatarImage,
                                          child: user.photoUrl.isEmpty
                                              ? const Icon(Icons.person, color: AppTheme.textSecondary)
                                              : null,
                                        ),
                                        title: Text(
                                          user.displayName,
                                          style: const TextStyle(
                                            fontFamily: 'Inter',
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                        subtitle: Text(
                                          '@${user.username}',
                                          style: const TextStyle(
                                            fontFamily: 'Inter',
                                            fontSize: 12,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                        trailing: isUserLoading
                                            ? const SizedBox(
                                                width: 24,
                                                height: 24,
                                                child: CircularProgressIndicator(
                                                  color: AppTheme.accentPrimary,
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  ElevatedButton(
                                                    onPressed: () async {
                                                      setSheetState(() => loadingUserId = user.uid);
                                                      await _userService.acceptFollowRequest(currentUid, user.uid);
                                                      final updated = await _loadNotificationLists();
                                                      setSheetState(() {
                                                        requests = updated['requests'];
                                                        followers = updated['followers'];
                                                        loadingUserId = null;
                                                      });
                                                      _loadCurrentUser();
                                                    },
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: AppTheme.accentPrimary,
                                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                                      minimumSize: const Size(60, 32),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                    ),
                                                    child: const Text(
                                                      'Accept',
                                                      style: TextStyle(
                                                        fontFamily: 'Inter',
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  OutlinedButton(
                                                    onPressed: () async {
                                                      setSheetState(() => loadingUserId = user.uid);
                                                      await _userService.declineFollowRequest(currentUid, user.uid);
                                                      final updated = await _loadNotificationLists();
                                                      setSheetState(() {
                                                        requests = updated['requests'];
                                                        followers = updated['followers'];
                                                        loadingUserId = null;
                                                      });
                                                      _loadCurrentUser();
                                                    },
                                                    style: OutlinedButton.styleFrom(
                                                      side: const BorderSide(color: Colors.white24),
                                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                                      minimumSize: const Size(40, 32),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                    ),
                                                    child: const Text(
                                                      'Decline',
                                                      style: TextStyle(
                                                        fontFamily: 'Inter',
                                                        fontSize: 12,
                                                        color: AppTheme.textSecondary,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                      );
                                    }),
                                    const SizedBox(height: 16),
                                  ],
                                  if (followers!.isNotEmpty) ...[
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 8),
                                      child: Text(
                                        'NEW FOLLOWERS',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.accentSecondary,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                    ),
                                    ...followers!.map((user) {
                                      final isUserLoading = loadingUserId == user.uid;
                                      return ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: CircleAvatar(
                                          radius: 20,
                                          backgroundColor: AppTheme.surface,
                                          backgroundImage: user.avatarImage,
                                          child: user.photoUrl.isEmpty
                                              ? const Icon(Icons.person, color: AppTheme.textSecondary)
                                              : null,
                                        ),
                                        title: Text(
                                          user.displayName,
                                          style: const TextStyle(
                                            fontFamily: 'Inter',
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                        subtitle: Text(
                                          '@${user.username}',
                                          style: const TextStyle(
                                            fontFamily: 'Inter',
                                            fontSize: 12,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                        trailing: isUserLoading
                                            ? const SizedBox(
                                                width: 24,
                                                height: 24,
                                                child: CircularProgressIndicator(
                                                  color: AppTheme.accentPrimary,
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : ElevatedButton(
                                                onPressed: () async {
                                                  setSheetState(() => loadingUserId = user.uid);
                                                  await _userService.followUser(currentUid, user.uid);
                                                  final updated = await _loadNotificationLists();
                                                  setSheetState(() {
                                                    requests = updated['requests'];
                                                    followers = updated['followers'];
                                                    loadingUserId = null;
                                                  });
                                                  _loadCurrentUser();
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: AppTheme.accentSecondary,
                                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                                  minimumSize: const Size(80, 32),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                ),
                                                child: const Text(
                                                  'Follow Back',
                                                  style: TextStyle(
                                                    fontFamily: 'Inter',
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                      );
                                    }),
                                  ],
                                ],
                              ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
