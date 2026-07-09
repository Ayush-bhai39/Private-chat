import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_chat/config/theme.dart';
import 'package:secure_chat/models/user_model.dart';
import 'package:secure_chat/screens/chat_screen.dart';
import 'package:secure_chat/screens/settings_screen.dart'; // import SpringTap

class DesktopChatPanel extends StatelessWidget {
  final UserModel otherUser;
  final VoidCallback onViewProfile;

  const DesktopChatPanel({
    super.key,
    required this.otherUser,
    required this.onViewProfile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF080710),
      child: Column(
        children: [
          // Header Bar
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.02),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withOpacity(0.06),
                  width: 1.0,
                ),
              ),
            ),
            child: Row(
              children: [
                // User Avatar and Name
                GestureDetector(
                  onTap: onViewProfile,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: AppTheme.surface,
                        backgroundImage: otherUser.avatarImage,
                        child: otherUser.photoUrl.isEmpty
                            ? const Icon(Icons.person, size: 20, color: AppTheme.textSecondary)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            otherUser.displayName,
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '@${otherUser.username}',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppTheme.accentPrimary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Call buttons
                Tooltip(
                  message: 'Audio Call',
                  textStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white),
                  child: SpringTap(
                    onTap: () {
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
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.04),
                      ),
                      child: const Icon(Icons.phone_rounded, size: 18, color: Colors.white70),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Tooltip(
                  message: 'Video Call',
                  textStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white),
                  child: SpringTap(
                    onTap: () {
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
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.04),
                      ),
                      child: const Icon(Icons.videocam_rounded, size: 18, color: Colors.white70),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Tooltip(
                  message: 'Contact Info',
                  textStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white),
                  child: SpringTap(
                    onTap: onViewProfile,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.04),
                      ),
                      child: const Icon(Icons.info_outline_rounded, size: 18, color: Colors.white70),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Chat View
          Expanded(
            child: ChatScreen(
              key: ValueKey(otherUser.uid), // Force recreation/reset on user switch
              otherUser: otherUser,
            ),
          ),
        ],
      ),
    );
  }
}
