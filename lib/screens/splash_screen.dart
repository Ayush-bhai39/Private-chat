import 'package:flutter/material.dart';
import 'package:secure_chat/config/theme.dart';
import 'package:secure_chat/services/auth_service.dart';
import 'package:secure_chat/services/user_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final AnimationController _titleController;
  late final AnimationController _subtitleController;
  late final AnimationController _loaderController;
  late final AnimationController _pulseController;

  late final Animation<double> _logoFade;
  late final Animation<double> _titleFade;
  late final Animation<double> _subtitleFade;
  late final Animation<double> _loaderFade;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _titleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _subtitleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _loaderController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _logoFade = CurvedAnimation(
      parent: _logoController,
      curve: Curves.easeOut,
    );
    _titleFade = CurvedAnimation(
      parent: _titleController,
      curve: Curves.easeOut,
    );
    _subtitleFade = CurvedAnimation(
      parent: _subtitleController,
      curve: Curves.easeOut,
    );
    _loaderFade = CurvedAnimation(
      parent: _loaderController,
      curve: Curves.easeOut,
    );

    _startAnimations();
    _navigateAfterDelay();
  }

  void _startAnimations() {
    _logoController.forward();

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _titleController.forward();
    });

    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _subtitleController.forward();
    });

    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) _loaderController.forward();
    });
  }

  Future<void> _navigateAfterDelay() async {
    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;

    final authService = AuthService();
    final user = authService.currentUser;

    if (user != null) {
      final userService = UserService();
      final userData = await userService.getUserData(user.uid);

      if (!mounted) return;

      if (userData != null && userData.username.isNotEmpty) {
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        Navigator.of(context).pushReplacementNamed('/username-setup');
      }
    } else {
      Navigator.of(context).pushReplacementNamed('/welcome');
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _titleController.dispose();
    _subtitleController.dispose();
    _loaderController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 3),
            // Logo
            FadeTransition(
              opacity: _logoFade,
              child: Center(
                child: Hero(
                  tag: 'app_logo',
                  child: Image.asset(
                    'assets/logo.png',
                    width: 120,
                    height: 120,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Title with gradient
            FadeTransition(
              opacity: _titleFade,
              child: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [
                    Color(0xFF6C63FF),
                    Color(0xFFA855F7),
                  ],
                ).createShader(bounds),
                child: const Text(
                  'Secret Chat',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Subtitle
            FadeTransition(
              opacity: _subtitleFade,
              child: const Text(
                'End-to-end encrypted',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  color: Color(0xFF8888A0),
                ),
              ),
            ),
            const Spacer(flex: 3),
            // Pulsing loader
            FadeTransition(
              opacity: _loaderFade,
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Opacity(
                    opacity: 0.3 + (_pulseController.value * 0.7),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 80),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          backgroundColor: Colors.white.withOpacity(0.05),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppTheme.accentPrimary.withOpacity(0.8),
                          ),
                          minHeight: 2,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}
