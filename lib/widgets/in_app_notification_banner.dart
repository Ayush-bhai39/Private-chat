import 'package:flutter/material.dart';
import 'package:secure_chat/config/theme.dart';
import 'package:secure_chat/models/user_model.dart';
import 'package:secure_chat/screens/settings_screen.dart'; // import SpringTap

class InAppNotificationBanner extends StatefulWidget {
  final UserModel sender;
  final String messageText;
  final Function(String) onReply;
  final VoidCallback onTap;

  const InAppNotificationBanner({
    super.key,
    required this.sender,
    required this.messageText,
    required this.onReply,
    required this.onTap,
  });

  static void show(
    BuildContext context, {
    required UserModel sender,
    required String messageText,
    required Function(String) onReply,
    required VoidCallback onTap,
  }) {
    final overlayState = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 24,
        left: 16,
        right: 16,
        child: SafeArea(
          child: Material(
            color: Colors.transparent,
            child: InAppNotificationBanner(
              sender: sender,
              messageText: messageText,
              onReply: (text) {
                onReply(text);
                if (overlayEntry.mounted) {
                  overlayEntry.remove();
                }
              },
              onTap: () {
                onTap();
                if (overlayEntry.mounted) {
                  overlayEntry.remove();
                }
              },
            ),
          ),
        ),
      ),
    );

    overlayState.insert(overlayEntry);

    // Auto dismiss after 6 seconds
    Future.delayed(const Duration(seconds: 6), () {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
      }
    });
  }

  @override
  State<InAppNotificationBanner> createState() => _InAppNotificationBannerState();
}

class _InAppNotificationBannerState extends State<InAppNotificationBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offsetAnimation;
  final _replyController = TextEditingController();
  bool _showReplyInput = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _replyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _offsetAnimation,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.surfaceLight, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              onTap: widget.onTap,
              leading: CircleAvatar(
                radius: 20,
                backgroundColor: AppTheme.surfaceLight,
                backgroundImage: widget.sender.avatarImage,
                child: widget.sender.photoUrl.isEmpty
                    ? const Icon(Icons.person, color: AppTheme.textSecondary)
                    : null,
              ),
              title: Text(
                widget.sender.displayName,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
              subtitle: Text(
                widget.messageText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              trailing: SpringTap(
                onTap: () {
                  setState(() {
                    _showReplyInput = !_showReplyInput;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.surfaceLight.withOpacity(0.5),
                  ),
                  child: Icon(
                    _showReplyInput ? Icons.keyboard_arrow_up_rounded : Icons.reply_rounded,
                    color: AppTheme.accentPrimary,
                    size: 20,
                  ),
                ),
              ),
            ),
            if (_showReplyInput)
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceLight.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(19),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: _replyController,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Type reply...',
                            hintStyle: TextStyle(color: Colors.white54, fontSize: 13),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SpringTap(
                      onTap: () {
                        final text = _replyController.text.trim();
                        if (text.isNotEmpty) {
                          widget.onReply(text);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: AppTheme.accentPrimary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
