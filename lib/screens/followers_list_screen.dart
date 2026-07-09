import 'package:flutter/material.dart';
import 'package:secure_chat/config/theme.dart';
import 'package:secure_chat/models/user_model.dart';
import 'package:secure_chat/services/user_service.dart';
import 'package:secure_chat/screens/settings_screen.dart'; // SpringTap

class FollowersListScreen extends StatefulWidget {
  const FollowersListScreen({super.key});

  @override
  State<FollowersListScreen> createState() => _FollowersListScreenState();
}

class _FollowersListScreenState extends State<FollowersListScreen> {
  final _userService = UserService();

  List<UserModel> _users = [];
  bool _isLoading = true;
  String _title = 'Users';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isLoading) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null) {
        _title = args['title'] as String? ?? 'Users';
        final uids = args['uids'] as List<String>? ?? [];
        _loadUsers(uids);
      }
    }
  }

  Future<void> _loadUsers(List<String> uids) async {
    final users = <UserModel>[];
    for (final uid in uids) {
      final user = await _userService.getUserData(uid);
      if (user != null) users.add(user);
    }
    if (mounted) {
      setState(() {
        _users = users;
        _isLoading = false;
      });
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
                          color: AppTheme.surfaceLight.withAlpha(77),
                        ),
                        child: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      _title,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_users.length}',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.accentPrimary))
                    : _users.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.people_outline_rounded,
                                  size: 64,
                                  color: AppTheme.textSecondary.withAlpha(77),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'No users found',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 16,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: _users.length,
                            itemBuilder: (context, index) {
                              final user = _users[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: AppTheme.surface.withAlpha(102),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppTheme.surfaceLight, width: 0.5),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                  onTap: () {
                                    Navigator.pushNamed(context, '/profile-view', arguments: user);
                                  },
                                  leading: CircleAvatar(
                                    radius: 22,
                                    backgroundColor: AppTheme.surfaceLight,
                                    backgroundImage: user.avatarImage,
                                    child: user.photoUrl.isEmpty
                                        ? const Icon(Icons.person, size: 20, color: AppTheme.textSecondary)
                                        : null,
                                  ),
                                  title: Text(
                                    user.displayName,
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '@${user.username}',
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      color: AppTheme.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  trailing: const Icon(
                                    Icons.chevron_right_rounded,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
