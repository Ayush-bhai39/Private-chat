import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_chat/config/theme.dart';
import 'package:secure_chat/models/user_model.dart';
import 'package:secure_chat/screens/settings_screen.dart';
import 'package:secure_chat/widgets/desktop_sidebar.dart';
import 'package:secure_chat/widgets/desktop_empty_state.dart';
import 'package:secure_chat/widgets/desktop_chat_panel.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:secure_chat/services/notification_service.dart';
import 'package:secure_chat/services/update_service.dart';

class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  DesktopTab _activeTab = DesktopTab.chats;
  UserModel? _selectedUser;
  UserModel? _detailUser;

  @override
  void initState() {
    super.initState();
    _initDesktopNotificationListening();
    _checkWindowsUpdates();
  }

  void _checkWindowsUpdates() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await UpdateService().checkForUpdates(context);
      } catch (e) {
        print("Error checking for Windows updates on startup: $e");
      }
    });
  }

  void _initDesktopNotificationListening() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      NotificationService.instance.init().then((_) {
        NotificationService.instance.startListening(user.uid);
      });
    }
  }

  @override
  void dispose() {
    NotificationService.instance.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showDetailPanel = _detailUser != null;

    return Scaffold(
      backgroundColor: const Color(0xFF080710),
      body: Row(
        children: [
          // 1. Sidebar (320px)
          DesktopSidebar(
            activeTab: _activeTab,
            onTabChanged: (tab) {
              setState(() {
                _activeTab = tab;
                if (tab == DesktopTab.settings) {
                  _selectedUser = null; // Unselect chat when viewing settings
                }
              });
            },
            selectedUser: _selectedUser,
            onUserSelected: (user) {
              setState(() {
                _selectedUser = user;
                _activeTab = DesktopTab.chats; // Switch to chats view
              });
            },
          ),

          // 2. Central Content Area (Expanded)
          Expanded(
            child: _buildCentralContent(),
          ),

          // 3. Detail Panel (320px, Conditional)
          if (showDetailPanel)
            _buildDetailPanel(),
        ],
      ),
    );
  }

  Widget _buildCentralContent() {
    if (_activeTab == DesktopTab.settings) {
      return const SettingsScreen();
    }

    if (_selectedUser != null) {
      return DesktopChatPanel(
        otherUser: _selectedUser!,
        onViewProfile: () {
          setState(() {
            _detailUser = _selectedUser;
          });
        },
      );
    }

    return const DesktopEmptyState();
  }

  Widget _buildDetailPanel() {
    final user = _detailUser!;

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0B1A),
        border: Border(
          left: BorderSide(
            color: Colors.white.withOpacity(0.06),
            width: 1.0,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Contact Info',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white38),
                  onPressed: () {
                    setState(() {
                      _detailUser = null;
                    });
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),

          // User Info
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Center(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 54,
                        backgroundColor: AppTheme.surface,
                        backgroundImage: user.avatarImage,
                        child: user.photoUrl.isEmpty
                            ? const Icon(Icons.person, size: 54, color: AppTheme.textSecondary)
                            : null,
                      ),
                       const SizedBox(height: 16),
                       Text(
                         user.displayName,
                         textAlign: TextAlign.center,
                         style: GoogleFonts.inter(
                           fontSize: 20,
                           fontWeight: FontWeight.bold,
                           color: Colors.white,
                         ),
                       ),
                       const SizedBox(height: 4),
                       Text(
                         '@${user.username}',
                         style: GoogleFonts.inter(
                           fontSize: 13,
                           color: AppTheme.accentPrimary,
                         ),
                       ),
                     ],
                  ),
                ),
                const SizedBox(height: 36),

                // Info Section
                _buildInfoSection('Email Address', user.email),
                _buildInfoSection('Security Fingerprint (E2EE)', _getFingerprintSummary(user.publicKey)),
                const SizedBox(height: 24),

                // Actions Section
                _buildActionTile(
                  icon: Icons.notifications_off_outlined,
                  title: 'Mute Notifications',
                  trailing: Switch(
                    value: false,
                    onChanged: (val) {},
                    activeColor: AppTheme.accentPrimary,
                  ),
                ),
                _buildActionTile(
                  icon: Icons.block_flipped,
                  title: 'Block Contact',
                  textColor: Colors.redAccent,
                  iconColor: Colors.redAccent,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white38,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    Color? textColor,
    Color? iconColor,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: iconColor ?? Colors.white70, size: 20),
      title: Text(
        title,
        style: GoogleFonts.inter(
          color: textColor ?? Colors.white,
          fontSize: 14,
        ),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }

  String _getFingerprintSummary(String keyPem) {
    if (keyPem.isEmpty) return 'No key generated';
    try {
      final cleanKey = keyPem
          .replaceAll('-----BEGIN PUBLIC KEY-----', '')
          .replaceAll('-----END PUBLIC KEY-----', '')
          .replaceAll('\n', '')
          .replaceAll('\r', '')
          .trim();
      if (cleanKey.length > 20) {
        return cleanKey.substring(0, 10) + '...' + cleanKey.substring(cleanKey.length - 10);
      }
      return cleanKey;
    } catch (_) {
      return 'Valid E2EE fingerprint';
    }
  }
}
