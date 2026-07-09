import 'dart:async';
import 'package:flutter/material.dart';
import 'package:secure_chat/config/theme.dart';
import 'package:secure_chat/models/user_model.dart';
import 'package:secure_chat/services/auth_service.dart';
import 'package:secure_chat/services/user_service.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final _searchController = TextEditingController();
  final _userService = UserService();
  final _authService = AuthService();

  List<UserModel> _results = [];
  bool _isSearching = false;
  Timer? _debounce;

  void _onSearchChanged(String query) {
    _debounce?.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final users = await _userService.searchUsers(query.trim());
        final currentUid = _authService.currentUser?.uid;
        final filtered = users.where((u) => u.uid != currentUid).toList();

        if (mounted) {
          setState(() {
            _results = filtered;
            _isSearching = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isSearching = false);
        }
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: Container(
          height: 40,
          margin: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            autofocus: true,
            style: const TextStyle(fontFamily: 'Inter', fontSize: 15),
            decoration: const InputDecoration(
              hintText: 'Search by username',
              hintStyle: TextStyle(color: AppTheme.textSecondary),
              prefixIcon: Icon(Icons.search_rounded, size: 20),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
      ),
      body: _isSearching
          ? const Center(
              child: CircularProgressIndicator(
                color: AppTheme.accentPrimary,
              ),
            )
          : _results.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 64,
                        color: AppTheme.textSecondary.withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchController.text.isEmpty
                            ? 'Search for users'
                            : 'No users found',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final user = _results[index];
                    return ListTile(
                      onTap: () {
                        Navigator.of(context).pushReplacementNamed(
                          '/profile-view',
                          arguments: user,
                        );
                      },
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
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '@${user.username}',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          color: AppTheme.accentPrimary,
                          fontSize: 13,
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
