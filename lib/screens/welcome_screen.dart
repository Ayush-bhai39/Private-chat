import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:secure_chat/config/theme.dart';
import 'package:secure_chat/services/auth_service.dart';
import 'package:secure_chat/services/user_service.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  final _authService = AuthService();
  final _userService = UserService();
  
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _resetEmailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLogin = true;
  bool _isSigningIn = false;
  bool _obscurePassword = true;
  bool _acceptTerms = false;

  late final AnimationController _logoController;
  late final AnimationController _titleController;
  late final AnimationController _formController;
  late final AnimationController _glowController;

  late final Animation<double> _logoFade;
  late final Animation<Offset> _logoSlide;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _formFade;
  late final Animation<Offset> _formSlide;

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
    _formController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _logoFade = CurvedAnimation(parent: _logoController, curve: Curves.easeOut);
    _logoSlide = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _logoController, curve: Curves.easeOut));

    _titleFade = CurvedAnimation(parent: _titleController, curve: Curves.easeOut);
    _titleSlide = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _titleController, curve: Curves.easeOut));

    _formFade = CurvedAnimation(parent: _formController, curve: Curves.easeOut);
    _formSlide = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _formController, curve: Curves.easeOut));

    _startAnimations();
  }

  void _startAnimations() {
    _logoController.forward();
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) _titleController.forward();
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _formController.forward();
    });
  }

  void _showEmailVerificationSentDialog(String email) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.mark_email_read_rounded, color: AppTheme.success),
              SizedBox(width: 8),
              Flexible(
                child: Text('Verify Your Email', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: Text(
            'We\'ve sent a verification email to $email. Please check your inbox (and spam folder) and click the verification link before logging in.',
            style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentPrimary),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showEmailVerificationRequiredDialog(String email) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Flexible(
                child: Text('Email Unverified', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: Text(
            'Your email address $email is not verified yet. Please click the verification link sent to your inbox to continue.',
            style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  setState(() => _isSigningIn = true);
                  final tempUser = await _authService.signInWithEmailAndPassword(email, _passwordController.text);
                  if (tempUser != null) {
                    await _authService.sendEmailVerification();
                    await _authService.signOut();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Verification email resent!'),
                          backgroundColor: AppTheme.success,
                        ),
                      );
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to resend: $e'),
                        backgroundColor: Colors.red.shade800,
                      ),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _isSigningIn = false);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentPrimary),
              child: const Text('Resend Link'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleAuthAction() async {
    if (!_acceptTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please accept the Privacy Policy & Terms to continue.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (!_formKey.currentState!.validate() || _isSigningIn) return;
    setState(() => _isSigningIn = true);

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final navigator = Navigator.of(context);

    try {
      dynamic user;
      if (_isLogin) {
        user = await _authService.signInWithEmailAndPassword(email, password);
        if (user != null) {
          final isVerified = await _authService.isEmailVerified();
          if (!isVerified) {
            await _authService.signOut();
            if (mounted) {
              _showEmailVerificationRequiredDialog(email);
            }
            return;
          }
        }
      } else {
        user = await _authService.signUpWithEmailAndPassword(email, password);
        if (user != null) {
          await _authService.sendEmailVerification();
          await _authService.signOut();
          if (mounted) {
            _showEmailVerificationSentDialog(email);
            setState(() {
              _isLogin = true;
            });
          }
          return;
        }
      }

      if (!mounted) return;

      if (user != null) {
        final userData = await _userService.getUserData(user.uid);
        if (!mounted) return;

        if (userData != null && userData.username.isNotEmpty) {
          navigator.pushReplacementNamed('/home');
        } else {
          navigator.pushReplacementNamed('/username-setup');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll(RegExp(r'\[.*?\]'), '')),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    if (!_acceptTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please accept the Privacy Policy & Terms to continue.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_isSigningIn) return;
    setState(() => _isSigningIn = true);
    final navigator = Navigator.of(context);

    try {
      final user = await _authService.signInWithGoogle();
      if (!mounted) return;

      if (user != null) {
        final userData = await _userService.getUserData(user.uid);
        if (!mounted) return;

        if (userData != null && userData.username.isNotEmpty) {
          navigator.pushReplacementNamed('/home');
        } else {
          navigator.pushReplacementNamed('/username-setup');
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMsg = e.toString();
        if (errorMsg.contains('10') || errorMsg.contains('developer_error')) {
          errorMsg = 'OAuth Configuration Error. Please register the SHA-1 fingerprint in the Firebase/Google console.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign in failed: $errorMsg'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  void _showForgotPasswordDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Reset Password',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter your registered email address to receive a password reset link.',
                style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _resetEmailController,
                style: const TextStyle(fontFamily: 'Inter', fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Email address',
                  prefixIcon: Icon(Icons.email_rounded, size: 20),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                final email = _resetEmailController.text.trim();
                if (email.isEmpty) return;
                Navigator.pop(context);
                try {
                  await _authService.sendPasswordResetEmail(email);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Password reset link sent to your email!'),
                        backgroundColor: AppTheme.success,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to send reset link: $e'),
                        backgroundColor: Colors.red.shade800,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                minimumSize: Size.zero,
              ),
              child: const Text('Send Reset Link', style: TextStyle(fontSize: 14)),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _logoController.dispose();
    _titleController.dispose();
    _formController.dispose();
    _glowController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _resetEmailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 450),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
              const SizedBox(height: 20),
              // Logo
              SlideTransition(
                position: _logoSlide,
                child: FadeTransition(
                  opacity: _logoFade,
                  child: Hero(
                    tag: 'app_logo',
                    child: Image.asset(
                      'assets/logo.png',
                      width: 90,
                      height: 90,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Title
              SlideTransition(
                position: _titleSlide,
                child: FadeTransition(
                  opacity: _titleFade,
                  child: Column(
                    children: [
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [AppTheme.accentPrimary, AppTheme.accentSecondary],
                        ).createShader(bounds),
                        child: const Text(
                          'Secret Chat',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Private messaging, redefined.',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Sign-in Form
              SlideTransition(
                position: _formSlide,
                child: FadeTransition(
                  opacity: _formFade,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Tab Selector
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _isLogin = true),
                                child: Column(
                                  children: [
                                    Text(
                                      'Log In',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: _isLogin ? AppTheme.textPrimary : AppTheme.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      height: 2,
                                      color: _isLogin ? AppTheme.accentPrimary : Colors.transparent,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _isLogin = false),
                                child: Column(
                                  children: [
                                    Text(
                                      'Sign Up',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: !_isLogin ? AppTheme.textPrimary : AppTheme.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      height: 2,
                                      color: !_isLogin ? AppTheme.accentPrimary : Colors.transparent,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Email Field
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(fontFamily: 'Inter', fontSize: 15),
                          decoration: const InputDecoration(
                            hintText: 'Email Address',
                            prefixIcon: Icon(Icons.email_rounded, size: 20),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your email';
                            }
                            if (!value.contains('@')) {
                              return 'Please enter a valid email';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Password Field
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: const TextStyle(fontFamily: 'Inter', fontSize: 15),
                          decoration: InputDecoration(
                            hintText: 'Password',
                            prefixIcon: const Icon(Icons.lock_rounded, size: 20),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                size: 20,
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your password';
                            }
                            if (value.length < 6) {
                              return 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        ),

                        // Forgot Password Link
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _showForgotPasswordDialog,
                            child: const Text(
                              'Forgot Password?',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: Colors.blueAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        // Privacy & Terms Consent Checkbox
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: _acceptTerms,
                                onChanged: (val) => setState(() => _acceptTerms = val ?? false),
                                activeColor: AppTheme.accentPrimary,
                                side: const BorderSide(color: AppTheme.textSecondary),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'I agree to the ',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            GestureDetector(
                              onTap: _showPrivacyPolicy,
                              child: const Text(
                                'Privacy Policy & Terms',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 12,
                                  color: AppTheme.accentPrimary,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Submit Button
                        Container(
                          height: 52,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(26),
                            gradient: const LinearGradient(
                              colors: [AppTheme.accentPrimary, AppTheme.accentSecondary],
                            ),
                          ),
                          child: ElevatedButton(
                            onPressed: _isSigningIn ? null : _handleAuthAction,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                            ),
                            child: _isSigningIn
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                  )
                                : Text(_isLogin ? 'Log In' : 'Sign Up'),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Divider OR
                        Row(
                          children: [
                            Expanded(child: Divider(color: AppTheme.surfaceLight, thickness: 1)),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                'OR',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  color: AppTheme.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Expanded(child: Divider(color: AppTheme.surfaceLight, thickness: 1)),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Google Sign-In Button
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isSigningIn ? null : _handleGoogleSignIn,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF1A1A2E),
                              disabledBackgroundColor: Colors.white.withOpacity(0.6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(26),
                              ),
                              elevation: 0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      'G',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF4285F4),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Continue with Google',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1A1A2E),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'End-to-end encrypted 🔒',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: Color(0xFF8888A0),
                ),
              ),
              const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  void _showPrivacyPolicy() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text(
            'Privacy Policy & Terms',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          content: const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '1. End-to-End Encryption',
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.accentPrimary),
                ),
                SizedBox(height: 4),
                Text(
                  'Your messages and media are encrypted locally before being sent. Nobody—including us—can decrypt or read them.',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.textSecondary),
                ),
                SizedBox(height: 12),
                Text(
                  '2. Account Data Collection',
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.accentPrimary),
                ),
                SizedBox(height: 4),
                Text(
                  'Signing in via Google or email registers your email and profile details to match you with other users. We do not track or share this information.',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.textSecondary),
                ),
                SizedBox(height: 12),
                Text(
                  '3. Data Storage & Deletion',
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.accentPrimary),
                ),
                SizedBox(height: 4),
                Text(
                  'Stories are hosted temporarily via Litterbox and are auto-deleted after 24 hours. Messages are stored securely on Firestore.',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(color: AppTheme.accentPrimary)),
            ),
          ],
        );
      },
    );
  }
}
