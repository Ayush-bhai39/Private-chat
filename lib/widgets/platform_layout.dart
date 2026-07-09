import 'dart:io';
import 'package:flutter/material.dart';
import 'package:secure_chat/screens/desktop_shell.dart';

class PlatformLayout extends StatelessWidget {
  final Widget mobileLayout;

  const PlatformLayout({
    super.key,
    required this.mobileLayout,
  });

  @override
  Widget build(BuildContext context) {
    // If running on desktop or the screen width is wide, render DesktopShell
    return LayoutBuilder(
      builder: (context, constraints) {
        if (Platform.isWindows || Platform.isMacOS || Platform.isLinux || constraints.maxWidth > 900) {
          return const DesktopShell();
        }
        return mobileLayout;
      },
    );
  }
}
