import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:window_manager/window_manager.dart';
import 'package:secure_chat/config/theme.dart';
import 'package:secure_chat/models/conversation_model.dart';
import 'package:secure_chat/models/user_model.dart';
import 'package:secure_chat/services/chat_service.dart';
import 'package:secure_chat/services/user_service.dart';
import 'package:secure_chat/widgets/conversation_tile.dart';
import 'package:secure_chat/screens/settings_screen.dart'; // import SpringTap
import 'package:secure_chat/models/story_model.dart';
import 'package:secure_chat/services/story_service.dart';
import 'package:secure_chat/widgets/skeleton_loader.dart';
import 'package:secure_chat/widgets/error_display_widget.dart';
import 'dart:async';

enum DesktopTab { chats, stories, calls, settings }

class DesktopSidebar extends StatefulWidget {
  final DesktopTab activeTab;
  final ValueChanged<DesktopTab> onTabChanged;
  final UserModel? selectedUser;
  final ValueChanged<UserModel> onUserSelected;

  const DesktopSidebar({
    super.key,
    required this.activeTab,
    required this.onTabChanged,
    required this.selectedUser,
    required this.onUserSelected,
  });

  @override
  State<DesktopSidebar> createState() => _DesktopSidebarState();
}

class _DesktopSidebarState extends State<DesktopSidebar> {
  final _chatService = ChatService();
  final _userService = UserService();
  final _auth = FirebaseAuth.instance;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  String _searchQuery = '';
  UserModel? _currentUser;
  bool _isLoadingUser = false;

  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadCurrentUser();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text;
        });
      }
    });
  }

  Future<void> _loadCurrentUser() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      setState(() => _isLoadingUser = true);
      final user = await _userService.getUserData(uid);
      if (mounted) {
        setState(() {
          _currentUser = user;
          _isLoadingUser = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0B1A),
        border: Border(
          right: BorderSide(
            color: Colors.white.withOpacity(0.06),
            width: 1.0,
          ),
        ),
      ),
      child: Column(
        children: [
          // Windows Window Title / Drag Area
          Container(
            height: 32,
            color: Colors.transparent,
            child: Row(
              children: [
                Expanded(
                  child: DragToMoveArea(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Secret Chat',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white38,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
                // Minimize Button
                _buildWindowButton(
                  icon: Icons.minimize_rounded,
                  onTap: () => windowManager.minimize(),
                ),
                // Maximize Button
                _buildWindowButton(
                  icon: Icons.crop_square_rounded,
                  onTap: () async {
                    final isMax = await windowManager.isMaximized();
                    if (isMax) {
                      windowManager.unmaximize();
                    } else {
                      windowManager.maximize();
                    }
                  },
                ),
                // Close Button
                _buildWindowButton(
                  icon: Icons.close_rounded,
                  hoverColor: Colors.red.shade900.withOpacity(0.8),
                  onTap: () => windowManager.close(),
                ),
              ],
            ),
          ),

          // Search Box
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search chats (Ctrl+F)...',
                  hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.white38),
                  prefixIcon: const Icon(Icons.search_rounded, size: 16, color: Colors.white38),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
              ),
            ),
          ),

          // Navigation Tabs Row
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildTabButton(DesktopTab.chats, Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Chats'),
                _buildTabButton(DesktopTab.stories, Icons.camera_alt_outlined, Icons.camera_alt_rounded, 'Stories'),
                _buildTabButton(DesktopTab.calls, Icons.phone_outlined, Icons.phone_rounded, 'Calls'),
                _buildTabButton(DesktopTab.settings, Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: Colors.white.withOpacity(0.06)),

          // Active Panel Content
          Expanded(
            child: widget.activeTab == DesktopTab.chats
                ? _buildChatsList()
                : widget.activeTab == DesktopTab.stories
                    ? _buildStoriesList()
                    : widget.activeTab == DesktopTab.calls
                        ? _buildCallsList()
                        : _buildSettingsList(),
          ),

          // User Profile Footer
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.01),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withOpacity(0.06),
                  width: 1.0,
                ),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppTheme.surface,
                  backgroundImage: _currentUser?.avatarImage,
                  child: _currentUser?.photoUrl.isEmpty ?? true
                      ? const Icon(Icons.person, size: 20, color: AppTheme.textSecondary)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _currentUser?.displayName ?? 'My Account',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppTheme.online,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Connected',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.white38,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.logout_rounded, size: 18, color: Colors.white38),
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                    if (context.mounted) {
                      Navigator.pushReplacementNamed(context, '/welcome');
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWindowButton({
    required IconData icon,
    required VoidCallback onTap,
    Color? hoverColor,
  }) {
    return SpringTap(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 32,
        alignment: Alignment.center,
        child: Icon(icon, size: 14, color: Colors.white38),
      ),
    );
  }

  Widget _buildTabButton(DesktopTab tab, IconData outlineIcon, IconData filledIcon, String tooltip) {
    final isActive = widget.activeTab == tab;
    return Tooltip(
      message: tooltip,
      textStyle: GoogleFonts.inter(fontSize: 11, color: Colors.white),
      child: SpringTap(
        onTap: () => widget.onTabChanged(tab),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? filledIcon : outlineIcon,
              size: 20,
              color: isActive ? AppTheme.accentPrimary : Colors.white38,
            ),
            const SizedBox(height: 4),
            Container(
              width: 16,
              height: 2,
              decoration: BoxDecoration(
                color: isActive ? AppTheme.accentPrimary : Colors.transparent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatsList() {
    return StreamBuilder<List<ConversationModel>>(
      stream: _chatService.getConversations(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorDisplayWidget(
            message: snapshot.error.toString(),
            onRetry: () => setState(() {}),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: 5,
            itemBuilder: (context, index) => _buildChatsSkeletonTile(),
          );
        }

        final conversations = snapshot.data ?? [];
        if (conversations.isEmpty) {
          return Center(
            child: Text(
              'No conversations yet',
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
            ),
          );
        }

        final filtered = conversations.where((c) {
          final name = c.otherUser.displayName.toLowerCase();
          return name.contains(_searchQuery.toLowerCase());
        }).toList();

        return ListView.builder(
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final conversation = filtered[index];
            final isSelected = widget.selectedUser?.uid == conversation.otherUser.uid;

            return Container(
              color: isSelected ? Colors.white.withOpacity(0.04) : Colors.transparent,
              child: Stack(
                children: [
                  ConversationTile(
                    conversation: conversation,
                    onTap: () => widget.onUserSelected(conversation.otherUser),
                  ),
                  if (isSelected)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 3.5,
                      child: Container(
                        color: AppTheme.accentPrimary,
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

  final _storyService = StoryService();

  Widget _buildStoriesList() {
    final currentUid = _auth.currentUser?.uid;
    return StreamBuilder<List<StoryModel>>(
      stream: _storyService.getStories(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorDisplayWidget(
            message: snapshot.error.toString(),
            onRetry: () => setState(() {}),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: 4,
            itemBuilder: (context, index) => _buildStoriesSkeletonTile(),
          );
        }

        final stories = snapshot.data ?? [];
        final grouped = <String, List<StoryModel>>{};
        for (final story in stories) {
          grouped.putIfAbsent(story.authorUid, () => []).add(story);
        }

        final hasOwnStory = currentUid != null && grouped.containsKey(currentUid);

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            ListTile(
              leading: Stack(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppTheme.surface,
                    backgroundImage: _currentUser?.avatarImage,
                    child: _currentUser?.photoUrl.isEmpty ?? true
                        ? const Icon(Icons.person, size: 22, color: AppTheme.textSecondary)
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(
                        color: AppTheme.accentPrimary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add, size: 10, color: Colors.white),
                    ),
                  ),
                ],
              ),
              title: Text(
                'My Story',
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                hasOwnStory ? 'Tap to view your story' : 'Add to my story',
                style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
              ),
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
                  Navigator.pushNamed(context, '/story-editor', arguments: {'source': 'gallery'});
                }
              },
            ),
            if (grouped.entries.where((e) => e.key != currentUid).isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'RECENT STORIES',
                  style: GoogleFonts.inter(color: AppTheme.accentPrimary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                ),
              ),
              ...grouped.entries
                  .where((e) => e.key != currentUid)
                  .map((entry) {
                final list = entry.value;
                final story = list.first;
                final allSeen = currentUid != null && list.every((s) => s.viewers.contains(currentUid));
                return ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: allSeen ? Colors.white24 : AppTheme.accentPrimary,
                        width: 2,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: AppTheme.surface,
                      backgroundImage: UserModel.getAvatarImageProvider(story.authorPhotoUrl),
                      child: story.authorPhotoUrl.isEmpty
                          ? Text(
                              story.authorDisplayName.isNotEmpty ? story.authorDisplayName[0].toUpperCase() : 'U',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                  ),
                  title: Text(
                    story.authorDisplayName,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    'Tap to view story',
                    style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.of(context).pushNamed(
                      '/story-viewer',
                      arguments: {
                        'stories': list,
                        'initialIndex': 0,
                      },
                    );
                  },
                );
              }),
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
                child: Center(
                  child: Text(
                    'No stories shared yet',
                    style: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCallsList() {
    return StreamBuilder<List<ConversationModel>>(
      stream: _chatService.getConversations(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorDisplayWidget(
            message: snapshot.error.toString(),
            onRetry: () => setState(() {}),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: 5,
            itemBuilder: (context, index) => _buildCallsSkeletonTile(),
          );
        }

        final conversations = snapshot.data ?? [];
        if (conversations.isEmpty) {
          return Center(
            child: Text(
              'No contacts to call yet',
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
            ),
          );
        }

        final filtered = conversations.where((c) {
          final name = c.otherUser.displayName.toLowerCase();
          return name.contains(_searchQuery.toLowerCase());
        }).toList();

        return ListView.builder(
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final conversation = filtered[index];
            final otherUser = conversation.otherUser;

            return ListTile(
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: AppTheme.surface,
                backgroundImage: otherUser.avatarImage,
                child: otherUser.photoUrl.isEmpty
                    ? const Icon(Icons.person, size: 20, color: AppTheme.textSecondary)
                    : null,
              ),
              title: Text(
                otherUser.displayName,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                '@${otherUser.username}',
                style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.phone_rounded, size: 16, color: Colors.white70),
                    onPressed: () {
                      Navigator.pushNamed(
                        context,
                        '/call',
                        arguments: {
                          'user': otherUser,
                          'type': 'audio',
                          'isIncoming': false,
                        },
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.videocam_rounded, size: 16, color: Colors.white70),
                    onPressed: () {
                      Navigator.pushNamed(
                        context,
                        '/call',
                        arguments: {
                          'user': otherUser,
                          'type': 'video',
                          'isIncoming': false,
                        },
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSettingsList() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildSettingsTile(
          icon: Icons.person_outline_rounded,
          title: 'Account Settings',
          onTap: () {
            // Switch central view to SettingsScreen in desktop shell
            widget.onTabChanged(DesktopTab.settings);
          },
        ),
        _buildSettingsTile(
          icon: Icons.lock_outline_rounded,
          title: 'Privacy & Keys',
          onTap: () {
            widget.onTabChanged(DesktopTab.settings);
          },
        ),
        _buildSettingsTile(
          icon: Icons.notifications_none_rounded,
          title: 'Notifications',
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildChatsSkeletonTile() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const SkeletonLoader(width: 44, height: 44, borderRadius: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonLoader(width: 120, height: 14),
                const SizedBox(height: 8),
                const SkeletonLoader(width: 180, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoriesSkeletonTile() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const SkeletonLoader(width: 40, height: 40, borderRadius: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonLoader(width: 100, height: 14),
                const SizedBox(height: 6),
                const SkeletonLoader(width: 140, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallsSkeletonTile() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const SkeletonLoader(width: 36, height: 36, borderRadius: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonLoader(width: 110, height: 14),
                const SizedBox(height: 6),
                const SkeletonLoader(width: 80, height: 10),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const SkeletonLoader(width: 28, height: 28, borderRadius: 14),
          const SizedBox(width: 8),
          const SkeletonLoader(width: 28, height: 28, borderRadius: 14),
        ],
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70, size: 20),
      title: Text(
        title,
        style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white30, size: 16),
      onTap: onTap,
    );
  }
}
