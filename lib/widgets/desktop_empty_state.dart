import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_chat/config/theme.dart';

class DesktopEmptyState extends StatefulWidget {
  const DesktopEmptyState({super.key});

  @override
  State<DesktopEmptyState> createState() => _DesktopEmptyStateState();
}

class _DesktopEmptyStateState extends State<DesktopEmptyState> with SingleTickerProviderStateMixin {
  late final AnimationController _logoController;
  late final Animation<double> _logoScale;

  @override
  void initState() {
    super.initState();
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _logoScale = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _logoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0F0C29),
            Color(0xFF1A1040),
            Color(0xFF080710),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _logoScale,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.accentPrimary.withOpacity(0.2),
                      blurRadius: 40,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/logo.png',
                  width: 130,
                  height: 130,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 130,
                      height: 130,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppTheme.primaryGradient,
                      ),
                      child: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 60,
                        color: Colors.white,
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Secret Chat for Windows',
              style: GoogleFonts.outfit(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'End-to-end encrypted messaging',
              style: GoogleFonts.inter(
                fontSize: 16,
                color: Colors.white54,
              ),
            ),
            const SizedBox(height: 48),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: AppTheme.online,
                ),
                const SizedBox(width: 8),
                Text(
                  'Your messages are private & E2EE protected',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.white38,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
