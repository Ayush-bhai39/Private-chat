import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:secure_chat/models/call_model.dart';
import 'package:secure_chat/models/user_model.dart';
import 'package:secure_chat/services/call_service.dart';
import 'package:secure_chat/services/user_service.dart';
import 'package:secure_chat/screens/settings_screen.dart'; // SpringTap

class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({super.key});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with TickerProviderStateMixin {
  final CallService _callService = CallService();
  final UserService _userService = UserService();

  CallModel? _callModel;
  UserModel? _callerUser;
  Timer? _timeoutTimer;
  bool _isAnswering = false;
  bool _isDeclining = false;

  // Animations
  late AnimationController _ringPulseController;
  late Animation<double> _ringPulse1;
  late Animation<double> _ringPulse2;
  late Animation<double> _ringPulse3;
  late AnimationController _slideController;
  late Animation<double> _slideAnimation;
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();

    // Triple ring pulse animation (outward expanding rings)
    _ringPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _ringPulse1 = Tween<double>(begin: 0.8, end: 1.8).animate(
      CurvedAnimation(
        parent: _ringPulseController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      ),
    );
    _ringPulse2 = Tween<double>(begin: 0.8, end: 1.6).animate(
      CurvedAnimation(
        parent: _ringPulseController,
        curve: const Interval(0.15, 0.8, curve: Curves.easeOut),
      ),
    );
    _ringPulse3 = Tween<double>(begin: 0.8, end: 1.4).animate(
      CurvedAnimation(
        parent: _ringPulseController,
        curve: const Interval(0.3, 0.9, curve: Curves.easeOut),
      ),
    );

    // Slide hint animation for answer button
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _slideAnimation = Tween<double>(begin: 0, end: 8).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeInOut),
    );

    // Glow animation
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    // Vibrate on incoming call
    HapticFeedback.heavyImpact();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_callModel == null) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null) {
        _callModel = args['callModel'] as CallModel?;

        if (_callModel != null) {
          _loadCallerInfo();

          // Auto-timeout: dismiss after 45 seconds
          _timeoutTimer = Timer(const Duration(seconds: 45), () {
            if (mounted && !_isAnswering) {
              _declineCall();
            }
          });
        }
      }
    }
  }

  Future<void> _loadCallerInfo() async {
    try {
      final user = await _userService.getUserData(_callModel!.callerUid);
      if (mounted) {
        setState(() => _callerUser = user);
      }
    } catch (e) {
      print('Error loading caller info: $e');
    }
  }

  Future<void> _answerCall() async {
    if (_isAnswering || _callModel == null) return;
    setState(() => _isAnswering = true);

    HapticFeedback.mediumImpact();
    _timeoutTimer?.cancel();

    // Navigate to call screen with incoming call data
    if (mounted) {
      Navigator.pushReplacementNamed(
        context,
        '/call',
        arguments: {
          'user': _callerUser ?? UserModel(
            uid: _callModel!.callerUid,
            email: '',
            displayName: _callModel!.callerName,
            photoUrl: _callModel!.callerPhotoUrl,
            username: '',
            publicKey: '',
            createdAt: DateTime.now(),
          ),
          'type': _callModel!.type,
          'isIncoming': true,
          'callModel': _callModel,
        },
      );
    }
  }

  Future<void> _declineCall() async {
    if (_isDeclining || _callModel == null) return;
    setState(() => _isDeclining = true);

    HapticFeedback.lightImpact();
    _timeoutTimer?.cancel();

    await _callService.declineCall(_callModel!.callId);
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _ringPulseController.dispose();
    _slideController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callerName = _callerUser?.displayName ?? _callModel?.callerName ?? 'Unknown';
    final isVideo = _callModel?.type == 'video';

    return Scaffold(
      backgroundColor: const Color(0xFF080710),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F0C29),
              Color(0xFF1A0A3E),
              Color(0xFF0F0C29),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 40),

              // Encrypted call badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.white.withOpacity(0.06),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_rounded, size: 13, color: Color(0xFF4ADE80)),
                    const SizedBox(width: 6),
                    Text(
                      'Encrypted ${isVideo ? 'Video' : 'Audio'} Call',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.7),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 2),

              // Animated pulsing avatar
              AnimatedBuilder(
                animation: _ringPulseController,
                builder: (context, child) {
                  return SizedBox(
                    width: 200,
                    height: 200,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outer pulse rings
                        _buildPulseRing(_ringPulse1.value, 0.15),
                        _buildPulseRing(_ringPulse2.value, 0.2),
                        _buildPulseRing(_ringPulse3.value, 0.25),

                        // Avatar
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6C63FF).withOpacity(
                                  _glowAnimation.value,
                                ),
                                blurRadius: 40,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 58,
                            backgroundColor: const Color(0xFF1E1B4B),
                            backgroundImage: _callerUser?.avatarImage,
                            child: _callerUser?.photoUrl.isEmpty ?? true
                                ? const Icon(Icons.person, size: 50, color: Colors.white38)
                                : null,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 30),

              // Caller name
              Text(
                callerName,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),

              // Call type label
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                    size: 18,
                    color: Colors.white54,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Incoming ${isVideo ? 'Video' : 'Audio'} Call',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),

              const Spacer(flex: 3),

              // Answer / Decline buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Decline button
                    _buildActionButton(
                      icon: Icons.call_end_rounded,
                      label: 'Decline',
                      color: const Color(0xFFEF4444),
                      onTap: _declineCall,
                      isLoading: _isDeclining,
                    ),

                    // Answer button
                    AnimatedBuilder(
                      animation: _slideAnimation,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(0, -_slideAnimation.value),
                          child: child,
                        );
                      },
                      child: _buildActionButton(
                        icon: isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                        label: 'Answer',
                        color: const Color(0xFF22C55E),
                        onTap: _answerCall,
                        isLoading: _isAnswering,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPulseRing(double scale, double opacity) {
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFF6C63FF).withOpacity(opacity * (2.0 - scale)),
            width: 2,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    return SpringTap(
      onTap: isLoading ? () {} : onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color, color.withOpacity(0.8)],
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.4),
                  blurRadius: 20,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: isLoading
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                : Icon(icon, color: Colors.white, size: 30),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: Colors.white.withOpacity(0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
