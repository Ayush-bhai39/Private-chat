import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:secure_chat/config/theme.dart';
import 'package:secure_chat/models/user_model.dart';
import 'package:secure_chat/services/auth_service.dart';
import 'package:secure_chat/services/user_service.dart';
import 'package:secure_chat/services/storage_service.dart';
import 'package:secure_chat/services/encryption_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _authService = AuthService();
  final _userService = UserService();
  final _storageService = StorageService();
  final _secureStorage = const FlutterSecureStorage();
  final _nameController = TextEditingController();

  UserModel? _currentUser;
  bool _isLoading = false;
  bool _isIncognitoKeyboard = false;
  bool _isPinLockEnabled = false;
  bool _isPrivateAccount = false;
  String _publicKeyFingerprint = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final user = _authService.currentUser;
    if (user != null) {
      final userData = await _userService.getUserData(user.uid);
      if (userData != null) {
        _currentUser = userData;
        _nameController.text = userData.displayName;
        _isPrivateAccount = userData.isPrivate;
        
        // Load keyboard setting
        final incognitoVal = await _secureStorage.read(key: 'incognito_keyboard_${user.uid}');
        _isIncognitoKeyboard = incognitoVal == 'true';

        // Load pin lock setting
        final pinLockVal = await _secureStorage.read(key: 'app_pin_${user.uid}');
        _isPinLockEnabled = pinLockVal != null && pinLockVal.isNotEmpty;

        // Public key fingerprint
        if (userData.publicKey.length > 50) {
          _publicKeyFingerprint = userData.publicKey
              .replaceAll('-----BEGIN PUBLIC KEY-----', '')
              .replaceAll('-----END PUBLIC KEY-----', '')
              .replaceAll('\n', '')
              .trim()
              .substring(0, 32) + '...';
        }
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _pickAndUploadImage() async {
    try {
      String? filePath;
      if (Platform.isWindows) {
        final result = await FilePicker.platform.pickFiles(type: FileType.image);
        if (result != null && result.files.single.path != null) {
          filePath = result.files.single.path;
        }
      } else {
        final pickedFile = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          imageQuality: 50,
          maxWidth: 500,
        );
        if (pickedFile != null) {
          filePath = pickedFile.path;
        }
      }
      if (filePath == null) return;

      setState(() => _isLoading = true);

      final file = File(filePath);
      // Upload using our StorageService (ImgBB with Base64 fallback)
      final uploadedUrl = await _storageService.uploadStoryMedia(file, true);

      final user = _authService.currentUser;
      if (user != null && _currentUser != null) {
        await _userService.updateProfile(
          uid: user.uid,
          displayName: _currentUser!.displayName,
          photoUrl: uploadedUrl,
        );
        await _loadSettings();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update DP: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfileName() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty || _currentUser == null) return;

    setState(() => _isLoading = true);
    try {
      final user = _authService.currentUser;
      if (user != null) {
        await _userService.updateProfile(
          uid: user.uid,
          displayName: newName,
          photoUrl: _currentUser!.photoUrl,
        );
        await _loadSettings();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Display name updated!')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update profile name: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _togglePrivacy(bool value) async {
    if (_currentUser == null) return;
    setState(() => _isPrivateAccount = value);
    try {
      final user = _authService.currentUser;
      if (user != null) {
        await _userService.toggleAccountPrivacy(user.uid, value);
      }
    } catch (e) {
      setState(() => _isPrivateAccount = !value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update account privacy: $e')),
      );
    }
  }

  Future<void> _regenerateKeys() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Regenerate Encryption Keys?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will generate a new pair of cryptographic keys. You will not be able to decrypt old messages on this device anymore, but it fixes issues where other users cannot send you messages due to missing keys.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentPrimary),
            child: const Text('Regenerate', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        final user = _authService.currentUser;
        if (user != null) {
          final keyPair = await EncryptionService.generateRSAKeyPair();
          final newPublicPem = EncryptionService.encodePublicKeyToPem(keyPair.publicKey);
          final newPrivatePem = EncryptionService.encodePrivateKeyToPem(keyPair.privateKey);

          await _secureStorage.write(key: 'rsa_private_key_${user.uid}', value: newPrivatePem);
          await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'publicKey': newPublicPem});

          await _loadSettings();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Cryptographic keys successfully regenerated!')),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to regenerate keys: $e')),
          );
        }
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleIncognito(bool value) async {
    final user = _authService.currentUser;
    if (user == null) return;
    setState(() => _isIncognitoKeyboard = value);
    await _secureStorage.write(
      key: 'incognito_keyboard_${user.uid}',
      value: value ? 'true' : 'false',
    );
  }

  Future<void> _togglePinLock(bool value) async {
    final user = _authService.currentUser;
    if (user == null) return;

    if (value) {
      // Set new PIN dialog
      final pin = await _showPinSetupDialog();
      if (pin != null && pin.length >= 4) {
        await _secureStorage.write(key: 'app_pin_${user.uid}', value: pin);
        setState(() => _isPinLockEnabled = true);
      } else {
        setState(() => _isPinLockEnabled = false);
      }
    } else {
      // Disable PIN lock
      await _secureStorage.delete(key: 'app_pin_${user.uid}');
      setState(() => _isPinLockEnabled = false);
    }
  }

  Future<String?> _showPinSetupDialog() async {
    final pinController = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Set Security PIN'),
          content: TextField(
            controller: pinController,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 4,
            decoration: const InputDecoration(
              hintText: 'Enter 4-digit PIN',
              counterText: '',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, pinController.text),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(80, 36),
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF080710), Color(0xFF0F0C20)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom Glassmorphic Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    if (Navigator.of(context).canPop()) ...[
                      SpringTap(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.surfaceLight.withOpacity(0.3),
                          ),
                          child: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                    const Text(
                      'Settings',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              
              Expanded(
                child: _isLoading && _currentUser == null
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        children: [
                          // Avatar and Profile Customization Card
                          Card(
                            color: AppTheme.surface.withOpacity(0.4),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  GestureDetector(
                                    onTap: _pickAndUploadImage,
                                    child: Stack(
                                      alignment: Alignment.bottomRight,
                                      children: [
                                        Hero(
                                          tag: 'profile_avatar',
                                          child: CircleAvatar(
                                            radius: 54,
                                            backgroundColor: AppTheme.surfaceLight,
                                            backgroundImage: _currentUser?.avatarImage,
                                            child: _currentUser?.photoUrl == null ||
                                                    _currentUser!.photoUrl.isEmpty
                                                ? const Icon(Icons.person, size: 48, color: AppTheme.textSecondary)
                                                : null,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: const BoxDecoration(
                                            color: AppTheme.accentPrimary,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: _nameController,
                                    style: const TextStyle(fontFamily: 'Inter', fontSize: 16, color: Colors.white),
                                    decoration: InputDecoration(
                                      labelText: 'Display Name',
                                      labelStyle: const TextStyle(color: AppTheme.textSecondary),
                                      suffixIcon: SpringTap(
                                        onTap: _saveProfileName,
                                        child: const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: Icon(Icons.check_rounded, color: AppTheme.accentPrimary),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '@${_currentUser?.username ?? ""}',
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 14,
                                      color: AppTheme.textSecondary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Account Privacy settings
                          _buildSectionTitle('Privacy'),
                          Card(
                            color: AppTheme.surface.withOpacity(0.4),
                            child: Column(
                              children: [
                                SwitchListTile(
                                  activeColor: AppTheme.accentPrimary,
                                  title: const Text('Private Account'),
                                  subtitle: const Text('Only approved followers can view your stories, notes and chat with you.'),
                                  value: _isPrivateAccount,
                                  onChanged: _togglePrivacy,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Security settings
                          _buildSectionTitle('Security Settings'),
                          Card(
                            color: AppTheme.surface.withOpacity(0.4),
                            child: Column(
                              children: [
                                SwitchListTile(
                                  activeColor: AppTheme.accentPrimary,
                                  title: const Text('Incognito Chat Typing'),
                                  subtitle: const Text('Disables keyboard auto-learning to protect inputs.'),
                                  value: _isIncognitoKeyboard,
                                  onChanged: _toggleIncognito,
                                ),
                                const Divider(height: 1, indent: 16, endIndent: 16),
                                SwitchListTile(
                                  activeColor: AppTheme.accentPrimary,
                                  title: const Text('App Security PIN Lock'),
                                  subtitle: const Text('Requires a 4-digit security PIN on app startup.'),
                                  value: _isPinLockEnabled,
                                  onChanged: _togglePinLock,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Key Verification
                          _buildSectionTitle('E2EE Verification Details'),
                          Card(
                            color: AppTheme.surface.withOpacity(0.4),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.verified_user_rounded, color: AppTheme.success, size: 20),
                                      SizedBox(width: 8),
                                      Text(
                                        'Verification Fingerprint',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _publicKeyFingerprint,
                                    style: const TextStyle(
                                      fontFamily: 'Courier',
                                      fontSize: 12,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'This cryptographic key ensures no third party, including database admins, can decrypt your chat sessions.',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 11,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Center(
                                    child: TextButton.icon(
                                      onPressed: _regenerateKeys,
                                      icon: const Icon(Icons.refresh_rounded, color: AppTheme.accentPrimary, size: 18),
                                      label: const Text(
                                        'Regenerate E2EE Keys',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          color: AppTheme.accentPrimary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary,
          fontSize: 12,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// SpringTap Widget for micro-animations
class SpringTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const SpringTap({super.key, required this.child, this.onTap});

  @override
  State<SpringTap> createState() => _SpringTapState();
}

class _SpringTapState extends State<SpringTap> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.94,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.reverse(),
      onTapUp: (_) {
        _controller.forward();
        widget.onTap?.call();
      },
      onTapCancel: () => _controller.forward(),
      child: ScaleTransition(
        scale: _controller,
        child: widget.child,
      ),
    );
  }
}
