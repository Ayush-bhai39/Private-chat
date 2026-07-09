import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:secure_chat/config/theme.dart';

class AnimatedSendButton extends StatefulWidget {
  final bool hasText;
  final VoidCallback? onPressed;

  const AnimatedSendButton({
    super.key,
    required this.hasText,
    this.onPressed,
  });

  @override
  State<AnimatedSendButton> createState() => _AnimatedSendButtonState();
}

class _AnimatedSendButtonState extends State<AnimatedSendButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    if (widget.hasText) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedSendButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasText != oldWidget.hasText) {
      if (widget.hasText) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onPressed,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.hasText ? null : AppTheme.surfaceLight,
            gradient: widget.hasText
                ? const LinearGradient(
                    colors: [AppTheme.accentPrimary, AppTheme.accentSecondary],
                  )
                : null,
          ),
          child: Center(
            child: Transform.rotate(
              angle: widget.hasText ? -math.pi / 6 : 0,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: Icon(
                  Icons.send_rounded,
                  key: ValueKey(widget.hasText),
                  color: widget.hasText ? Colors.white : AppTheme.textSecondary,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
