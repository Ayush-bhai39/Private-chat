import 'package:flutter/material.dart';
import 'package:secure_chat/config/theme.dart';
import 'package:secure_chat/models/user_model.dart';
import 'package:secure_chat/services/auth_service.dart';
import 'package:secure_chat/services/user_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:secure_chat/screens/settings_screen.dart'; // for SpringTap
import 'package:secure_chat/services/update_service.dart';

class ProfileViewScreen extends StatefulWidget {
  const ProfileViewScreen({super.key});

  @override
  State<ProfileViewScreen> createState() => _ProfileViewScreenState();
}

class _ProfileViewScreenState extends State<ProfileViewScreen> {
  final _authService = AuthService();
  final _userService = UserService();

  UserModel? _targetUser;
  bool _isLoading = false;
  int _storiesCount = 0;
  bool _isFollowing = false;
  bool _hasRequested = false;
  bool _isUpdateAvailable = false;
  Map<String, dynamic>? _updateInfo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_targetUser == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is UserModel) {
        _targetUser = args;
        _loadFreshProfile();
      }
    }
  }

  Future<void> _loadFreshProfile() async {
    if (_targetUser == null) return;
    setState(() => _isLoading = true);

    try {
      final currentUid = _authService.currentUser!.uid;
      final freshData = await _userService.getUserData(_targetUser!.uid);
      if (freshData != null) {
        setState(() {
          _targetUser = freshData;
          _isFollowing = freshData.followers.contains(currentUid);
          _hasRequested = freshData.followRequests.contains(currentUid);
        });

        // Load stories count if public or following
        if (!freshData.isPrivate || _isFollowing) {
          final oneDayAgo = DateTime.now().subtract(const Duration(hours: 24));
          final storiesSnap = await FirebaseFirestore.instance
              .collection('stories')
              .where('authorUid', isEqualTo: freshData.uid)
              .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(oneDayAgo))
              .get();
          setState(() {
            _storiesCount = storiesSnap.docs.length;
          });
        } else {
          setState(() {
            _storiesCount = 0;
          });
        }

        // Check for updates
        final updateInfo = await UpdateService().getUpdateInfo();
        if (updateInfo != null) {
          setState(() {
            _isUpdateAvailable = true;
            _updateInfo = updateInfo;
          });
        }
      }
    } catch (e) {
      print('Error loading profile: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleFollowAction() async {
    if (_targetUser == null) return;
    final currentUid = _authService.currentUser!.uid;

    setState(() => _isLoading = true);
    try {
      if (_isFollowing || _hasRequested) {
        // Unfollow or Cancel Request
        await _userService.unfollowUser(currentUid, _targetUser!.uid);
      } else {
        // Follow or Request Follow
        await _userService.followUser(currentUid, _targetUser!.uid);
      }
      await _loadFreshProfile();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Action failed: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_targetUser == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isLocked = _targetUser!.isPrivate && !_isFollowing;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF080710), Color(0xFF0F0C20)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    SpringTap(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.surfaceLight.withOpacity(0.3),
                        ),
                        child: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '@${_targetUser!.username}',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    const SizedBox(height: 12),
                    // Profile info row
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 46,
                          backgroundColor: AppTheme.surfaceLight,
                          backgroundImage: _targetUser!.avatarImage,
                          child: _targetUser!.photoUrl.isEmpty
                              ? const Icon(Icons.person, size: 36, color: AppTheme.textSecondary)
                              : null,
                        ),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildStatItem('Stories', _storiesCount.toString()),
                              _buildStatItem(
                                'Followers',
                                _targetUser!.followers.length.toString(),
                                onTap: () {
                                  Navigator.pushNamed(
                                    context,
                                    '/followers-list',
                                    arguments: {
                                      'title': 'Followers',
                                      'uids': _targetUser!.followers,
                                    },
                                  );
                                },
                              ),
                              _buildStatItem(
                                'Following',
                                _targetUser!.following.length.toString(),
                                onTap: () {
                                  Navigator.pushNamed(
                                    context,
                                    '/followers-list',
                                    arguments: {
                                      'title': 'Following',
                                      'uids': _targetUser!.following,
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Display Name
                    Text(
                      _targetUser!.displayName,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          _targetUser!.isPrivate ? '🔒 Private Profile' : '🌐 Public Profile',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        if (_targetUser!.following.contains(_authService.currentUser!.uid)) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceLight.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Follows you',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Actions Row: Follow/Requested/Unfollow + Message
                    Row(
                      children: [
                        Expanded(
                          child: SpringTap(
                            onTap: _isLoading ? null : _handleFollowAction,
                            child: Container(
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _isFollowing
                                    ? AppTheme.surfaceLight.withOpacity(0.4)
                                    : _hasRequested
                                        ? AppTheme.surfaceLight.withOpacity(0.2)
                                        : AppTheme.accentPrimary,
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: _isFollowing || _hasRequested
                                      ? AppTheme.surfaceLight
                                      : Colors.transparent,
                                  width: 1,
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : Text(
                                      _isFollowing
                                          ? 'Following'
                                          : _hasRequested
                                              ? 'Requested'
                                              : (_targetUser!.following.contains(_authService.currentUser!.uid)
                                                  ? 'Follow Back'
                                                  : 'Follow'),
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: _isFollowing || _hasRequested
                                            ? AppTheme.textSecondary
                                            : Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        if (_isUpdateAvailable) ...[
                          const SizedBox(width: 12),
                          SpringTap(
                            onTap: () {
                              UpdateService().showUpdateDialog(
                                context,
                                _updateInfo!['versionName'],
                                _updateInfo!['downloadUrl'],
                                _updateInfo!['forceUpdate'],
                              );
                            },
                            child: Container(
                              height: 44,
                              width: 44,
                              decoration: BoxDecoration(
                                color: AppTheme.accentPrimary.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(color: AppTheme.accentPrimary.withOpacity(0.5), width: 1),
                              ),
                              child: const Icon(
                                Icons.system_update_rounded,
                                color: AppTheme.accentPrimary,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                        if (!_targetUser!.isPrivate || _isFollowing) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: SpringTap(
                              onTap: () {
                                Navigator.pushNamed(
                                  context,
                                  '/chat',
                                  arguments: _targetUser,
                                );
                              },
                              child: Container(
                                height: 44,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceLight.withOpacity(0.4),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(color: AppTheme.surfaceLight, width: 1),
                                ),
                                child: const Text(
                                    'Message',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Locked account banner
                    if (isLocked) ...[
                      const Divider(),
                      const SizedBox(height: 48),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 64,
                            color: Colors.white.withOpacity(0.3),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'This Account is Private',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              'Follow @${_targetUser!.username} to see their stories, notes, and start encrypted chat sessions.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                color: AppTheme.textSecondary.withOpacity(0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      // If public/following, show a clean message that details verification status
                      Card(
                        color: AppTheme.surface.withOpacity(0.4),
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.lock_outline_rounded, color: AppTheme.success, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'E2EE Verified Chat Session',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              Text(
                                'You can chat securely. Every sent text message is encrypted on your device and can only be decrypted by this recipient.',
                                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
