import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:secure_chat/config/theme.dart';
import 'package:secure_chat/models/user_model.dart';
import 'package:secure_chat/services/auth_service.dart';
import 'package:secure_chat/services/user_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:secure_chat/screens/settings_screen.dart'; // import SpringTap
import 'package:secure_chat/services/update_service.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _authService = AuthService();
  final _userService = UserService();

  UserModel? _currentUser;
  List<UserModel> _pendingRequests = [];
  bool _isLoading = false;
  int _storiesCount = 0;
  bool _isUpdateAvailable = false;
  Map<String, dynamic>? _updateInfo;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    setState(() => _isLoading = true);
    final user = _authService.currentUser;
    if (user != null) {
      final userData = await _userService.getUserData(user.uid);
      if (userData != null) {
        _currentUser = userData;

        // Fetch follow requests
        final requests = await _userService.getFollowRequests(user.uid);
        _pendingRequests = requests;

        // Fetch user's active stories count
        try {
          final oneDayAgo = DateTime.now().subtract(const Duration(hours: 24));
          final storiesSnap = await FirebaseFirestore.instance
              .collection('stories')
              .where('authorUid', isEqualTo: user.uid)
              .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(oneDayAgo))
              .get();
          _storiesCount = storiesSnap.docs.length;
        } catch (e) {
          _storiesCount = 0;
        }

        // Fetch updates
        final updateInfo = await UpdateService().getUpdateInfo();
        if (updateInfo != null) {
          _isUpdateAvailable = true;
          _updateInfo = updateInfo;
        } else {
          _isUpdateAvailable = false;
          _updateInfo = null;
        }
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _acceptRequest(String requesterUid) async {
    if (_currentUser == null) return;
    try {
      await _userService.acceptFollowRequest(_currentUser!.uid, requesterUid);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Follow request accepted!')),
      );
      await _loadProfileData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to accept request: $e')),
      );
    }
  }

  Future<void> _declineRequest(String requesterUid) async {
    if (_currentUser == null) return;
    try {
      await _userService.declineFollowRequest(_currentUser!.uid, requesterUid);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Follow request declined.')),
      );
      await _loadProfileData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to decline request: $e')),
      );
    }
  }

  Future<void> _handleSignOut() async {
    await _authService.signOut();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/welcome', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              // Custom Header Bar
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
                      _currentUser?.username != null ? '@${_currentUser!.username}' : 'Profile',
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
                child: _isLoading && _currentUser == null
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _loadProfileData,
                        color: AppTheme.accentPrimary,
                        backgroundColor: AppTheme.surface,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 12),
                            // Instagram-style Profile Header Row
                            Row(
                              children: [
                                Hero(
                                  tag: 'profile_avatar',
                                  child: CircleAvatar(
                                    radius: 46,
                                    backgroundColor: AppTheme.surfaceLight,
                                    backgroundImage: _currentUser?.avatarImage,
                                    child: _currentUser?.photoUrl == null ||
                                            _currentUser!.photoUrl.isEmpty
                                        ? const Icon(Icons.person, size: 36, color: AppTheme.textSecondary)
                                        : null,
                                  ),
                                ),
                                Expanded(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      _buildStatItem('Stories', _storiesCount.toString()),
                                      _buildStatItem(
                                        'Followers',
                                        _currentUser?.followers.length.toString() ?? '0',
                                        onTap: () {
                                          if (_currentUser != null) {
                                            Navigator.pushNamed(
                                              context,
                                              '/followers-list',
                                              arguments: {
                                                'title': 'Followers',
                                                'uids': _currentUser!.followers,
                                              },
                                            );
                                          }
                                        },
                                      ),
                                      _buildStatItem(
                                        'Following',
                                        _currentUser?.following.length.toString() ?? '0',
                                        onTap: () {
                                          if (_currentUser != null) {
                                            Navigator.pushNamed(
                                              context,
                                              '/followers-list',
                                              arguments: {
                                                'title': 'Following',
                                                'uids': _currentUser!.following,
                                              },
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // User Profile Names
                            Text(
                              _currentUser?.displayName ?? '',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _currentUser?.isPrivate == true ? '🔒 Private Account' : '🌐 Public Account',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Edit Profile & Logout Buttons (WhatsApp / Instagram styling)
                            Row(
                              children: [
                                Expanded(
                                  child: SpringTap(
                                    onTap: () async {
                                      await Navigator.pushNamed(context, '/settings');
                                      _loadProfileData();
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
                                        'Edit Profile',
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
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      decoration: BoxDecoration(
                                        color: AppTheme.accentPrimary.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(22),
                                        border: Border.all(color: AppTheme.accentPrimary.withOpacity(0.5), width: 1),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.system_update_rounded, color: AppTheme.accentPrimary, size: 18),
                                          SizedBox(width: 8),
                                          Text(
                                            'Update App',
                                            style: TextStyle(
                                              fontFamily: 'Inter',
                                              color: AppTheme.accentPrimary,
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 12),
                                SpringTap(
                                  onTap: _handleSignOut,
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: AppTheme.error.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(color: AppTheme.error.withOpacity(0.4), width: 1),
                                    ),
                                    child: const Icon(
                                      Icons.logout_rounded,
                                      size: 20,
                                      color: AppTheme.error,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // Invite Friends Card
                            SpringTap(
                              onTap: () {
                                Clipboard.setData(const ClipboardData(
                                  text: "Hey! Let's chat securely on Secret Chat. It's fully end-to-end encrypted, has zero ads, and you can download it in 1 click here: https://ayush-bhai39.github.io/Private-chat/"
                                ));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                      'Invitation link copied! Share it with your friends. 📲',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white,
                                      ),
                                    ),
                                    backgroundColor: AppTheme.accentPrimary,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppTheme.surfaceLight.withOpacity(0.3),
                                      AppTheme.surfaceLight.withOpacity(0.15),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: AppTheme.surfaceLight.withOpacity(0.4),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: const LinearGradient(
                                          colors: [AppTheme.accentPrimary, AppTheme.accentSecondary],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.share_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Invite Friends',
                                            style: TextStyle(
                                              fontFamily: 'Inter',
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Copy download link to invite others',
                                            style: TextStyle(
                                              fontFamily: 'Inter',
                                              fontSize: 12,
                                              color: AppTheme.textSecondary.withOpacity(0.8),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.copy_rounded,
                                      color: AppTheme.textSecondary,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 32),

                            // Follow Requests panel
                            if (_currentUser?.isPrivate == true) ...[
                              _buildSectionTitle('Follow Requests (${_pendingRequests.length})'),
                              if (_pendingRequests.isEmpty)
                                Card(
                                  color: AppTheme.surface.withOpacity(0.2),
                                  child: const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Center(
                                      child: Text(
                                        'No pending requests',
                                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                                      ),
                                    ),
                                  ),
                                )
                              else
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _pendingRequests.length,
                                  itemBuilder: (context, index) {
                                    final reqUser = _pendingRequests[index];
                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      color: AppTheme.surface.withOpacity(0.4),
                                      child: ListTile(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                        leading: CircleAvatar(
                                          radius: 20,
                                          backgroundColor: AppTheme.surfaceLight,
                                          backgroundImage: reqUser.avatarImage,
                                          child: reqUser.photoUrl.isEmpty
                                              ? const Icon(Icons.person, size: 20, color: AppTheme.textSecondary)
                                              : null,
                                        ),
                                        title: Text(
                                          reqUser.displayName,
                                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                                        ),
                                        subtitle: Text(
                                          '@${reqUser.username}',
                                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SpringTap(
                                              onTap: () => _acceptRequest(reqUser.uid),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.accentPrimary,
                                                  borderRadius: BorderRadius.circular(16),
                                                ),
                                                child: const Text(
                                                  'Accept',
                                                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            SpringTap(
                                              onTap: () => _declineRequest(reqUser.uid),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.surfaceLight,
                                                  borderRadius: BorderRadius.circular(16),
                                                ),
                                                child: const Text(
                                                  'Decline',
                                                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ],
                        ),
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

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary,
          fontSize: 12,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
