import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:secure_chat/models/call_model.dart';
import 'package:secure_chat/models/user_model.dart';
import 'package:secure_chat/services/call_service.dart';
import 'package:secure_chat/services/user_service.dart';
import 'package:secure_chat/screens/settings_screen.dart'; // SpringTap
import 'package:wakelock_plus/wakelock_plus.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with TickerProviderStateMixin {
  final CallService _callService = CallService();

  // Renderers
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  // State
  String _callStatus = 'ringing'; // ringing, connecting, connected, ended
  String _callType = 'audio';
  UserModel? _otherUser;
  bool _isIncoming = false;
  CallModel? _callModel;
  Timer? _durationTimer;
  int _callDurationSeconds = 0;
  bool _controlsVisible = true;
  Timer? _controlsHideTimer;

  // Animations
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _initRenderers();
    WakelockPlus.enable();

    // Pulse animation for ringing state
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Fade animation for controls
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );
    _fadeAnimation = _fadeController;
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null && _otherUser == null) {
      _otherUser = args['user'] as UserModel?;
      _callType = args['type'] as String? ?? 'audio';
      _isIncoming = args['isIncoming'] as bool? ?? false;
      _callModel = args['callModel'] as CallModel?;

      // Set up callbacks
      _callService.onLocalStream = (stream) {
        if (mounted) {
          setState(() {
            _localRenderer.srcObject = stream;
          });
        }
      };

      _callService.onRemoteStream = (stream) {
        if (mounted) {
          setState(() {
            _remoteRenderer.srcObject = stream;
            _callStatus = 'connected';
            _startDurationTimer();
            _pulseController.stop();
          });
        }
      };

      _callService.onCallStateChanged = (callModel) {
        if (mounted) {
          setState(() {
            _callModel = callModel;
            if (callModel.status == 'answered' && _callStatus == 'ringing') {
              _callStatus = 'connecting';
            }
          });
        }
      };

      _callService.onCallEnded = () {
        if (mounted) {
          setState(() => _callStatus = 'ended');
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) Navigator.pop(context);
          });
        }
      };

      // Start or answer the call
      if (_isIncoming && _callModel != null) {
        _answerCall();
      } else if (!_isIncoming && _otherUser != null) {
        _startCall();
      }
    }
  }

  Future<void> _startCall() async {
    try {
      setState(() => _callStatus = 'ringing');

      // We need caller's UserModel — fetch from Firestore
      final callerUid = FirebaseAuth.instance.currentUser?.uid;
      if (callerUid == null || _otherUser == null) return;

      final callerUser = await UserService().getUserData(callerUid);
      if (callerUser == null) return;

      await _callService.startCall(callerUser, _otherUser!, _callType);
    } catch (e) {
      print('Error starting call: $e');
      if (mounted) {
        String errorMsg = e.toString();
        if (Platform.isWindows) {
          errorMsg = 'Error: ${errorMsg.replaceAll('Exception:', '')}';
        } else {
          if (errorMsg.contains('Permission') || errorMsg.contains('permission')) {
            errorMsg = 'Camera and Microphone permissions are required to make calls.';
          } else if (errorMsg.contains('decodePublicKey')) {
            errorMsg = 'This contact has not initialized their security keys yet.';
          } else if (errorMsg.contains('GetUserMedia') || errorMsg.contains('Devices')) {
            errorMsg = 'Failed to access camera or microphone.';
          } else {
            errorMsg = 'Could not initiate call: ${errorMsg.replaceAll('Exception:', '')}';
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _answerCall() async {
    try {
      setState(() => _callStatus = 'connecting');
      await _callService.answerCall(_callModel!);
    } catch (e) {
      print('Error answering call: $e');
      if (mounted) {
        String errorMsg = e.toString();
        if (Platform.isWindows) {
          errorMsg = 'Error: ${errorMsg.replaceAll('Exception:', '')}';
        } else {
          if (errorMsg.contains('Permission') || errorMsg.contains('permission')) {
            errorMsg = 'Camera and Microphone permissions are required to answer calls.';
          } else {
            errorMsg = 'Failed to answer call: ${errorMsg.replaceAll('Exception:', '')}';
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _callDurationSeconds++);
      }
    });
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _toggleControlsVisibility() {
    if (_callType != 'video') return;
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _fadeController.forward();
      _controlsHideTimer?.cancel();
      _controlsHideTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _callStatus == 'connected') {
          setState(() => _controlsVisible = false);
          _fadeController.reverse();
        }
      });
    } else {
      _fadeController.reverse();
    }
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _controlsHideTimer?.cancel();
    _pulseController.dispose();
    _fadeController.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = _callType == 'video';

    return Scaffold(
      backgroundColor: const Color(0xFF080710),
      body: GestureDetector(
        onTap: isVideo ? _toggleControlsVisibility : null,
        child: Stack(
          children: [
            // Background
            if (isVideo && _callStatus == 'connected')
              _buildVideoView()
            else
              _buildAudioBackground(),

            // Controls overlay
            SafeArea(
              child: Column(
                children: [
                  _buildTopBar(),
                  const Spacer(),
                  if (!isVideo || _callStatus != 'connected')
                    _buildCallerInfo(),
                  if (!isVideo || _callStatus != 'connected')
                    const Spacer(),
                  _buildCallControls(),
                  const SizedBox(height: 40),
                ],
              ),
            ),

            // Local video PiP (video call only)
            if (isVideo && _callStatus == 'connected')
              _buildLocalVideoPip(),
          ],
        ),
      ),
    );
  }

  // ─── Background for audio calls ───
  Widget _buildAudioBackground() {
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
    );
  }

  // ─── Full-screen remote video ───
  Widget _buildVideoView() {
    return SizedBox.expand(
      child: RepaintBoundary(
        child: RTCVideoView(
          _remoteRenderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        ),
      ),
    );
  }

  // ─── Local video PiP ───
  Widget _buildLocalVideoPip() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 60,
      right: 16,
      child: GestureDetector(
        onTap: () => _callService.switchCamera(),
        child: Container(
          width: 100,
          height: 140,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: RepaintBoundary(
            child: RTCVideoView(
              _localRenderer,
              mirror: true,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
        ),
      ),
    );
  }

  // ─── Top bar ───
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SpringTap(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.1),
              ),
              child: const Icon(Icons.arrow_back_rounded, color: Colors.white70, size: 20),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.white.withOpacity(0.08),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_rounded, size: 12, color: Color(0xFF4ADE80)),
                const SizedBox(width: 4),
                Text(
                  'Encrypted ${_callType == 'video' ? 'Video' : 'Audio'} Call',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          const SizedBox(width: 36), // Balance the back button
        ],
      ),
    );
  }

  // ─── Caller info (avatar, name, status) ───
  Widget _buildCallerInfo() {
    final statusText = {
      'ringing': _isIncoming ? 'Incoming call...' : 'Calling...',
      'connecting': 'Connecting...',
      'connected': _formatDuration(_callDurationSeconds),
      'ended': 'Call Ended',
    }[_callStatus] ?? 'Calling...';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Animated avatar
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            final scale = _callStatus == 'ringing' ? _pulseAnimation.value : 1.0;
            return Transform.scale(
              scale: scale,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _callStatus == 'connected'
                        ? const Color(0xFF4ADE80)
                        : Colors.white24,
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (_callStatus == 'connected'
                              ? const Color(0xFF4ADE80)
                              : const Color(0xFF6C63FF))
                          .withOpacity(0.3),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 52,
                  backgroundColor: const Color(0xFF1E1B4B),
                  backgroundImage: _otherUser?.avatarImage,
                  child: _otherUser?.photoUrl.isEmpty ?? true
                      ? const Icon(Icons.person, size: 48, color: Colors.white38)
                      : null,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 20),

        // Name
        Text(
          _otherUser?.displayName ?? 'Unknown',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),

        // Status
        Text(
          statusText,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            color: _callStatus == 'connected'
                ? const Color(0xFF4ADE80)
                : Colors.white60,
          ),
        ),
      ],
    );
  }

  // ─── Call control buttons ───
  Widget _buildCallControls() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top row: mute, hold, speaker, video
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildControlButton(
                  icon: _callService.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  label: _callService.isMuted ? 'Unmute' : 'Mute',
                  isActive: _callService.isMuted,
                  onTap: () {
                    setState(() => _callService.toggleMute());
                  },
                ),
                _buildControlButton(
                  icon: _callService.isOnHold ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  label: _callService.isOnHold ? 'Resume' : 'Hold',
                  isActive: _callService.isOnHold,
                  onTap: () {
                    setState(() => _callService.toggleHold());
                  },
                ),
                _buildControlButton(
                  icon: _callService.isSpeakerOn
                      ? Icons.volume_up_rounded
                      : Icons.volume_down_rounded,
                  label: 'Speaker',
                  isActive: _callService.isSpeakerOn,
                  onTap: () {
                    setState(() => _callService.toggleSpeaker());
                  },
                ),
                if (_callType == 'video')
                  _buildControlButton(
                    icon: _callService.isVideoEnabled
                        ? Icons.videocam_rounded
                        : Icons.videocam_off_rounded,
                    label: 'Camera',
                    isActive: !_callService.isVideoEnabled,
                    onTap: () {
                      setState(() => _callService.toggleVideo());
                    },
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // Hang up button
            SpringTap(
              onTap: () => _callService.endCall(),
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEF4444).withOpacity(0.4),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 30),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return SpringTap(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive
                  ? Colors.white.withOpacity(0.25)
                  : Colors.white.withOpacity(0.08),
              border: Border.all(
                color: isActive ? Colors.white30 : Colors.white10,
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}
