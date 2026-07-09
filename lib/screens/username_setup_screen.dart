import 'dart:async';
import 'package:flutter/material.dart';
import 'package:secure_chat/config/theme.dart';
import 'package:secure_chat/services/auth_service.dart';
import 'package:secure_chat/services/user_service.dart';

class UsernameSetupScreen extends StatefulWidget {
  const UsernameSetupScreen({super.key});

  @override
  State<UsernameSetupScreen> createState() => _UsernameSetupScreenState();
}

enum UsernameStatus { empty, tooShort, checking, available, taken, invalid }

class _UsernameSetupScreenState extends State<UsernameSetupScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _userService = UserService();
  final _authService = AuthService();
  final _usernameRegex = RegExp(r'^[a-z0-9_]+$');

  Timer? _debounce;
  UsernameStatus _status = UsernameStatus.empty;
  bool _isSubmitting = false;

  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
  }

  void _onUsernameChanged(String value) {
    _debounce?.cancel();

    final trimmed = value.trim().toLowerCase();

    if (trimmed.isEmpty) {
      setState(() => _status = UsernameStatus.empty);
      return;
    }

    if (trimmed.length < 3) {
      setState(() => _status = UsernameStatus.tooShort);
      return;
    }

    if (trimmed.length > 20) {
      setState(() => _status = UsernameStatus.invalid);
      return;
    }

    if (!_usernameRegex.hasMatch(trimmed)) {
      setState(() => _status = UsernameStatus.invalid);
      return;
    }

    setState(() => _status = UsernameStatus.checking);

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final isAvailable = await _userService.isUsernameAvailable(trimmed);
        if (mounted && _controller.text.trim().toLowerCase() == trimmed) {
          setState(() {
            _status =
                isAvailable ? UsernameStatus.available : UsernameStatus.taken;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => _status = UsernameStatus.invalid);
        }
      }
    });
  }

  Future<void> _handleSubmit() async {
    if (_status != UsernameStatus.available || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      final username = _controller.text.trim().toLowerCase();
      final user = _authService.currentUser!;

      await _userService.createUser(
        uid: user.uid,
        email: user.email ?? '',
        displayName: user.displayName ?? username,
        photoUrl: user.photoURL ?? '',
        username: username,
      );

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red.shade800,
          ),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  Widget _buildStatusWidget() {
    IconData? icon;
    String text;
    Color color;

    switch (_status) {
      case UsernameStatus.empty:
        return const SizedBox(height: 24);
      case UsernameStatus.tooShort:
        icon = Icons.info_outline;
        text = 'Username must be at least 3 characters';
        color = const Color(0xFF8888A0);
        break;
      case UsernameStatus.checking:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.accentPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Checking availability...',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        );
      case UsernameStatus.available:
        icon = Icons.check_circle;
        text = 'Username is available';
        color = const Color(0xFF4CAF50);
        break;
      case UsernameStatus.taken:
        icon = Icons.cancel;
        text = 'Username is already taken';
        color = const Color(0xFFEF5350);
        break;
      case UsernameStatus.invalid:
        icon = Icons.warning_amber_rounded;
        text = 'Only lowercase letters, numbers, and underscores';
        color = const Color(0xFFFF9800);
        break;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            color: color,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isValid = _status == UsernameStatus.available;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                Text(
                  'Choose your username',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This is how people will find you',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 40),
                TextField(
                  controller: _controller,
                  onChanged: _onUsernameChanged,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 18,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    prefixText: '@',
                    prefixStyle: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 18,
                      color: AppTheme.accentPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    hintText: 'username',
                    hintStyle: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 18,
                      color: AppTheme.textSecondary.withOpacity(0.4),
                    ),
                    filled: true,
                    fillColor: AppTheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppTheme.accentPrimary,
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                  ),
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _handleSubmit(),
                ),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: SizedBox(
                    key: ValueKey(_status),
                    height: 24,
                    child: _buildStatusWidget(),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: isValid ? 1.0 : 0.4,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        gradient: const LinearGradient(
                          colors: [
                            AppTheme.accentPrimary,
                            AppTheme.accentSecondary,
                          ],
                        ),
                      ),
                      child: ElevatedButton(
                        onPressed: isValid && !_isSubmitting
                            ? _handleSubmit
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Continue',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                const Spacer(flex: 3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
