import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:secure_chat/services/encryption_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:secure_chat/config/theme.dart';
import 'package:secure_chat/models/user_model.dart';
import 'package:secure_chat/models/message_model.dart';
import 'package:secure_chat/services/auth_service.dart';
import 'package:secure_chat/services/chat_service.dart';
import 'package:secure_chat/services/notification_service.dart';
import 'package:secure_chat/services/storage_service.dart';
import 'package:secure_chat/widgets/message_bubble.dart';
import 'package:secure_chat/widgets/animated_send_button.dart';
import 'package:secure_chat/screens/settings_screen.dart'; // import SpringTap
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:secure_chat/services/call_service.dart';

class ChatScreen extends StatefulWidget {
  static String? activeChatId;
  final UserModel? otherUser;

  const ChatScreen({super.key, this.otherUser});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _chatService = ChatService();
  final _authService = AuthService();
  final _secureStorage = const FlutterSecureStorage();
  final Map<String, DecryptedMessage> _decryptedCache = {};
  MessageModel? _replyingToMessage;
  String? _replyingToMessageText;

  bool _hasText = false;
  UserModel? _otherUser;
  String _chatId = '';
  bool _isIncognitoKeyboard = false;
  bool _showEmojiPanel = false;
  bool _isLoadingMedia = false;

  // Custom native Emojis list
  final List<String> _emojis = [
    '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣', '😊', '😇',
    '🙂', '🙃', '😉', '😌', '😍', '🥰', '😘', '😗', '😙', '😚',
    '😋', '😛', '😝', '😜', '🤪', '🤨', '🧐', '🤓', '😎', '🥸',
    '🥳', '😏', '😒', '😞', '😔', '😟', '😕', '🙁', '☹️', '😣',
    '👍', '👎', '👊', '✊', '🤛', '🤜', '🤞', '✌️', '🤟', '🤘',
    '👌', '🤌', '🤙', '👈', '👉', '👆', '🖕', '👇', '☝️', '✋',
    '🤚', '🖐️', '🖖', '👋', '💪', '🦾', '✍️', '🙏', '🤝', '❤️',
    '🔥', '✨', '🎉', '🌟', '💥', '💯', '💩', '🤡', '👽', '🤖'
  ];

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
  }

  Future<void> _sendMediaMessage(File file, String mediaType) async {
    if (_otherUser == null) return;

    final repliedId = _replyingToMessage?.id;
    final repliedSenderUid = _replyingToMessage?.senderUid;
    final repliedSenderName = _replyingToMessage != null
        ? (_replyingToMessage!.senderUid == _authService.currentUser?.uid ? 'You' : _otherUser!.displayName)
        : null;
    final repliedText = _replyingToMessageText;

    setState(() {
      _isLoadingMedia = true;
      _replyingToMessage = null;
      _replyingToMessageText = null;
    });

    try {
      final storageService = StorageService();
      
      // 1. Generate predefined AES-256 key (32 bytes) and IV (16 bytes)
      final random = Random.secure();
      final aesKey = Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256)));
      final iv = Uint8List.fromList(List<int>.generate(16, (_) => random.nextInt(256)));

      // 2. Read and encrypt file bytes E2EE style - in background isolate to prevent lag!
      final plainBytes = await file.readAsBytes();
      final encryptedBytes = await EncryptionService.encryptFileBytesInBackground(plainBytes, aesKey, iv);

      // 3. Write encrypted bytes to a temporary file
      final tempDir = Directory.systemTemp;
      final originalName = file.path.split(Platform.pathSeparator).last;
      final encFile = File('${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}_$originalName');
      await encFile.writeAsBytes(encryptedBytes);

      String contentType = 'application/octet-stream';
      if (mediaType == 'image') {
        contentType = 'image/jpeg';
      } else if (mediaType == 'video') {
        contentType = 'video/mp4';
      } else {
        final ext = file.path.split('.').last.toLowerCase();
        if (ext == 'pdf') {
          contentType = 'application/pdf';
        } else if (ext == 'xml') {
          contentType = 'application/xml';
        } else if (ext == 'doc' || ext == 'docx') {
          contentType = 'application/msword';
        }
      }

      String plaintextBody = '📎 Media File';
      if (mediaType == 'image') {
        plaintextBody = '📷 Photo';
      } else if (mediaType == 'video') {
        plaintextBody = '🎥 Video';
      } else {
        plaintextBody = '📄 $originalName';
      }

      // Generate local Firestore ID
      final messageId = FirebaseFirestore.instance.collection('chats').doc().id;

      // 4. Send placeholder message instantly with 'uploading' status
      await _chatService.sendMessage(
        _otherUser!.uid,
        plaintextBody,
        mediaUrl: 'uploading',
        mediaType: mediaType,
        repliedMessageId: repliedId,
        repliedMessageSenderUid: repliedSenderUid,
        repliedMessageSenderName: repliedSenderName,
        repliedMessageText: repliedText,
        predefinedAesKey: aesKey,
        predefinedIv: iv,
        status: 'uploading',
        messageId: messageId,
      );

      // 5. Upload the encrypted file in background
      storageService.uploadMessageMedia(encFile, contentType).then((mediaUrl) async {
        await _chatService.updateMediaMessageUrl(
          chatId: _chatId,
          messageId: messageId,
          mediaUrl: mediaUrl,
          recipientUid: _otherUser!.uid,
          senderUid: _authService.currentUser!.uid,
          plaintext: plaintextBody,
          mediaType: mediaType,
        );
        if (mounted) {
          setState(() {
            _isLoadingMedia = false;
          });
        }
      }).catchError((e) {
        print("Background upload failed: $e");
        FirebaseFirestore.instance
            .collection('chats')
            .doc(_chatId)
            .collection('messages')
            .doc(messageId)
            .update({'status': 'failed'});
        if (mounted) {
          setState(() {
            _isLoadingMedia = false;
          });
        }
      });

    } catch (e) {
      print("Error sending media message: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to encrypt/send media: $e')),
        );
        setState(() {
          _isLoadingMedia = false;
        });
      }
    }
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: AppTheme.surface.withOpacity(0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: AppTheme.surfaceLight, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Send Media & Files',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildAttachmentOption(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    colors: [const Color(0xFF9C27B0), const Color(0xFFE91E63)],
                    onTap: () async {
                      Navigator.pop(context);
                      if (Platform.isWindows) {
                        final result = await FilePicker.platform.pickFiles(type: FileType.image);
                        if (result != null && result.files.single.path != null) {
                          _sendMediaMessage(File(result.files.single.path!), 'image');
                        }
                      } else {
                        final picker = ImagePicker();
                        final picked = await picker.pickImage(source: ImageSource.gallery);
                        if (picked != null) {
                          _sendMediaMessage(File(picked.path), 'image');
                        }
                      }
                    },
                  ),
                  _buildAttachmentOption(
                    icon: Icons.camera_alt_rounded,
                    label: 'Camera',
                    colors: [const Color(0xFFFF5722), const Color(0xFFFF9800)],
                    onTap: () async {
                      Navigator.pop(context);
                      if (Platform.isWindows) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Camera capture is not supported on desktop. Please upload an existing photo from Gallery.'),
                            backgroundColor: AppTheme.accentPrimary,
                          ),
                        );
                      } else {
                        final picker = ImagePicker();
                        final picked = await picker.pickImage(source: ImageSource.camera);
                        if (picked != null) {
                          _sendMediaMessage(File(picked.path), 'image');
                        }
                      }
                    },
                  ),
                  _buildAttachmentOption(
                    icon: Icons.videocam_rounded,
                    label: 'Video',
                    colors: [const Color(0xFF00E676), const Color(0xFF00B0FF)],
                    onTap: () async {
                      Navigator.pop(context);
                      if (Platform.isWindows) {
                        final result = await FilePicker.platform.pickFiles(type: FileType.video);
                        if (result != null && result.files.single.path != null) {
                          _sendMediaMessage(File(result.files.single.path!), 'video');
                        }
                      } else {
                        final picker = ImagePicker();
                        final picked = await picker.pickVideo(source: ImageSource.gallery);
                        if (picked != null) {
                          _sendMediaMessage(File(picked.path), 'video');
                        }
                      }
                    },
                  ),
                  _buildAttachmentOption(
                    icon: Icons.insert_drive_file_rounded,
                    label: 'Document',
                    colors: [const Color(0xFF00B0FF), const Color(0xFF2979FF)],
                    onTap: () async {
                      Navigator.pop(context);
                      final result = await FilePicker.platform.pickFiles(type: FileType.any);
                      if (result != null && result.files.single.path != null) {
                        _sendMediaMessage(File(result.files.single.path!), 'file');
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required String label,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SpringTap(
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: colors.first.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_otherUser == null) {
      if (widget.otherUser != null) {
        _otherUser = widget.otherUser;
      } else {
        final args = ModalRoute.of(context)?.settings.arguments;
        if (args is UserModel) {
          _otherUser = args;
        }
      }
      if (_otherUser != null) {
        final currentUid = _authService.currentUser!.uid;
        _chatId = _chatService.getChatId(currentUid, _otherUser!.uid);
        ChatScreen.activeChatId = _chatId;
        _loadSecuritySettings();
        _chatService.markChatAsRead(_otherUser!.uid);
        NotificationService.instance.clearAllNotifications();
      }
    }
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.otherUser != oldWidget.otherUser && widget.otherUser != null) {
      _otherUser = widget.otherUser;
      final currentUid = _authService.currentUser!.uid;
      _chatId = _chatService.getChatId(currentUid, _otherUser!.uid);
      ChatScreen.activeChatId = _chatId;
      _textController.clear();
      _replyingToMessage = null;
      _replyingToMessageText = null;
      _decryptedCache.clear();
      _loadSecuritySettings();
      _chatService.markChatAsRead(_otherUser!.uid);
      NotificationService.instance.clearAllNotifications();
      setState(() {});
    }
  }

  Future<void> _loadSecuritySettings() async {
    final currentUid = _authService.currentUser!.uid;
    final val = await _secureStorage.read(key: 'incognito_keyboard_$currentUid');
    setState(() {
      _isIncognitoKeyboard = val == 'true';
    });
  }

  void _onTextChanged() {
    final hasText = _textController.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  Future<DecryptedMessage> _getDecryptedText(MessageModel message) async {
    if (_decryptedCache.containsKey(message.id)) {
      return _decryptedCache[message.id]!;
    }
    final decrypted = await _chatService.decryptMessage(message);
    _decryptedCache[message.id] = decrypted;
    return decrypted;
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _otherUser == null) return;

    final repliedId = _replyingToMessage?.id;
    final repliedSenderUid = _replyingToMessage?.senderUid;
    final repliedSenderName = _replyingToMessage?.senderUid == _authService.currentUser?.uid
        ? 'You'
        : _otherUser?.displayName;
    final repliedText = _replyingToMessageText;

    _textController.clear();
    setState(() {
      _showEmojiPanel = false;
      _replyingToMessage = null;
      _replyingToMessageText = null;
    });

    try {
      await _chatService.sendMessage(
        _otherUser!.uid,
        text,
        repliedMessageId: repliedId,
        repliedMessageSenderUid: repliedSenderUid,
        repliedMessageSenderName: repliedSenderName,
        repliedMessageText: repliedText,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: ${e.toString()}'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  Future<void> _sendGifMessage(String gifUrl) async {
    if (_otherUser == null) return;
    try {
      await _chatService.sendMessage(
        _otherUser!.uid,
        '[GIF]',
        mediaUrl: gifUrl,
        mediaType: 'gif',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send GIF: $e')),
      );
    }
  }

  void _insertEmoji(String emoji) {
    final text = _textController.text;
    final selection = _textController.selection;
    
    // If no active selection, append to end
    if (selection.start == -1 || selection.end == -1) {
      _textController.text = text + emoji;
    } else {
      final newText = text.replaceRange(selection.start, selection.end, emoji);
      _textController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + emoji.length),
      );
    }
    setState(() => _hasText = true);
  }

  void _showMessageActions(MessageModel message, String decryptedText) {
    final isMine = message.senderUid == _authService.currentUser?.uid;
    final isDeleted = message.isDeleted;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.surface.withOpacity(0.9),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: AppTheme.surfaceLight, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              // Glowing Glass Floating Reactions Row (WhatsApp Style)
              if (!isDeleted)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLight.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: ['👍', '❤️', '😂', '😮', '😢', '🙏'].map((emoji) {
                      final hasThisReact = message.reactions[_authService.currentUser?.uid] == emoji;
                      return SpringTap(
                        onTap: () {
                          _chatService.reactToMessage(_otherUser!.uid, message.id, emoji);
                          Navigator.pop(context);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hasThisReact ? AppTheme.accentPrimary.withOpacity(0.2) : Colors.transparent,
                          ),
                          child: Text(emoji, style: const TextStyle(fontSize: 24)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              const SizedBox(height: 16),

              // Option Tiles
              if (!isDeleted) ...[
                ListTile(
                  leading: const Icon(Icons.reply_rounded, color: Colors.white70),
                  title: const Text('Reply', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _replyingToMessage = message;
                      _replyingToMessageText = decryptedText;
                    });
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.copy_rounded, color: Colors.white70),
                  title: const Text('Copy Message', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: decryptedText));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 1)),
                    );
                  },
                ),
              ],
              if (isMine && !isDeleted)
                ListTile(
                  leading: const Icon(Icons.edit_rounded, color: Colors.white70),
                  title: const Text('Edit Message', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _showEditDialog(message, decryptedText);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppTheme.error),
                title: const Text('Delete for Me', style: TextStyle(color: Colors.white)),
                onTap: () {
                  _chatService.deleteMessageForMe(_otherUser!.uid, message.id);
                  Navigator.pop(context);
                },
              ),
              if (isMine && !isDeleted)
                ListTile(
                  leading: const Icon(Icons.delete_forever_rounded, color: AppTheme.error),
                  title: const Text('Delete for Everyone', style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.bold)),
                  onTap: () {
                    _chatService.deleteMessageForEveryone(_otherUser!.uid, message.id);
                    Navigator.pop(context);
                  },
                ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showEditDialog(MessageModel message, String currentText) {
    final editController = TextEditingController(text: currentText);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Message'),
          content: TextField(
            controller: editController,
            maxLines: 4,
            minLines: 1,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Edit message text',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final newText = editController.text.trim();
                if (newText.isNotEmpty && newText != currentText) {
                  _chatService.editMessage(_otherUser!.uid, message.id, newText);
                  // Refresh decryption cache
                  _decryptedCache[message.id] = DecryptedMessage(
                    newText,
                    _decryptedCache[message.id]?.repliedText,
                  );
                }
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(minimumSize: const Size(80, 36)),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showGifPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return GifPickerSheet(
          onGifSelected: (gifUrl) => _sendGifMessage(gifUrl),
        );
      },
    );
  }

  @override
  void dispose() {
    ChatScreen.activeChatId = null;
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _startCall(String type) {
    if (_otherUser == null) return;

    Navigator.pushNamed(
      context,
      '/call',
      arguments: {
        'user': _otherUser,
        'type': type,
        'isIncoming': false,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_otherUser == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0E1A),
        body: SizedBox.shrink(),
      );
    }

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
              // Premium Glass Header (WhatsApp + Instagram inspired)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    SpringTap(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.surfaceLight.withOpacity(0.3),
                        ),
                        child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SpringTap(
                      onTap: () {
                        // Open profile view screen
                        Navigator.pushNamed(
                          context,
                          '/profile-view',
                          arguments: _otherUser,
                        );
                      },
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: AppTheme.surface,
                        backgroundImage: _otherUser!.avatarImage,
                        child: _otherUser!.photoUrl.isEmpty
                            ? const Icon(Icons.person, size: 20, color: AppTheme.textSecondary)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.pushNamed(
                            context,
                            '/profile-view',
                            arguments: _otherUser,
                          );
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _otherUser!.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.lock_outline_rounded, size: 10, color: AppTheme.success),
                                const SizedBox(width: 4),
                                Text(
                                  'end-to-end encrypted',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 11,
                                    color: Colors.white.withOpacity(0.5),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Call buttons
                    SpringTap(
                      onTap: () => _startCall('audio'),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.surfaceLight.withOpacity(0.15),
                        ),
                        child: const Icon(Icons.call_rounded, color: Colors.white70, size: 20),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SpringTap(
                      onTap: () => _startCall('video'),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.surfaceLight.withOpacity(0.15),
                        ),
                        child: const Icon(Icons.videocam_rounded, color: Colors.white70, size: 20),
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: StreamBuilder<List<MessageModel>>(
                  stream: _chatService.getMessages(_chatId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final messages = snapshot.data ?? [];
                    if (messages.isNotEmpty) {
                      _chatService.markChatAsRead(_otherUser!.uid);
                    }

                    if (messages.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 48,
                              color: AppTheme.accentPrimary.withOpacity(0.3),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'E2EE Verified Chat Session',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 40),
                              child: Text(
                                'All messages are fully encrypted. No one else has access to the cryptographic keys but you and @${_otherUser!.username}.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 12,
                                  color: AppTheme.textSecondary.withOpacity(0.6),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        final isMine = message.senderUid == _authService.currentUser?.uid;

                        // Synchronous Cache Bypass to avoid FutureBuilder lag during scrolls
                        final cached = _decryptedCache[message.id];
                        if (cached != null) {
                          return GestureDetector(
                            onLongPress: () => _showMessageActions(message, cached.text),
                            child: MessageBubble(
                              message: message,
                              text: cached.text,
                              isMine: isMine,
                              repliedText: cached.repliedText,
                            ),
                          );
                        }

                        return FutureBuilder<DecryptedMessage>(
                          future: _getDecryptedText(message),
                          builder: (context, textSnapshot) {
                            final decrypted = textSnapshot.data;
                            final decryptedText = decrypted?.text ?? 'Decrypting...';
                            final repliedText = decrypted?.repliedText;
                            return GestureDetector(
                              onLongPress: () => _showMessageActions(message, decryptedText),
                              child: MessageBubble(
                                message: message,
                                text: decryptedText,
                                isMine: isMine,
                                repliedText: repliedText,
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),

              // Glass Capsule Input bar (WhatsApp E2EE layout)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.surface.withOpacity(0.3),
                  border: const Border(
                    top: BorderSide(
                      color: AppTheme.surfaceLight,
                      width: 0.5,
                    ),
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isLoadingMedia) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceLight.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentPrimary),
                              ),
                              SizedBox(width: 12),
                              Text(
                                "Encrypting and uploading media...",
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_replyingToMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceLight.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(10),
                            border: Border(
                              left: BorderSide(
                                color: AppTheme.accentPrimary,
                                width: 3.5,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _replyingToMessage!.senderUid == _authService.currentUser?.uid
                                          ? 'Replying to You'
                                          : 'Replying to ${_otherUser?.displayName ?? "User"}',
                                      style: const TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.accentPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _replyingToMessageText ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 12,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.textSecondary),
                                onPressed: () {
                                  setState(() {
                                    _replyingToMessage = null;
                                    _replyingToMessageText = null;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                      Row(
                        children: [
                          // Emoji panel toggler
                          SpringTap(
                            onTap: () {
                              setState(() {
                                _showEmojiPanel = !_showEmojiPanel;
                                if (_showEmojiPanel) {
                                  // Hide system keyboard
                                  FocusScope.of(context).unfocus();
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                _showEmojiPanel ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined,
                                color: Colors.white70,
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),

                          // Attachment menu button
                          SpringTap(
                            onTap: _showAttachmentMenu,
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(
                                Icons.add_rounded,
                                color: Colors.white70,
                                size: 24,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),

                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceLight.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: TextField(
                                controller: _textController,
                                autocorrect: !_isIncognitoKeyboard,
                                enableSuggestions: !_isIncognitoKeyboard,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 15,
                                  color: Colors.white,
                                ),
                                maxLines: 4,
                                minLines: 1,
                                onTap: () {
                                  if (_showEmojiPanel) {
                                    setState(() {
                                      _showEmojiPanel = false;
                                    });
                                  }
                                },
                                decoration: const InputDecoration(
                                  hintText: 'Type a secure message...',
                                  hintStyle: TextStyle(color: Colors.white54),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          AnimatedSendButton(
                            hasText: _hasText,
                            onPressed: _hasText ? _sendMessage : null,
                          ),
                        ],
                      ),

                      // Native Emoji Picker Panel
                      if (_showEmojiPanel)
                        Container(
                          height: 240,
                          margin: const EdgeInsets.only(top: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.surface.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.surfaceLight, width: 0.5),
                          ),
                          child: GridView.builder(
                            padding: const EdgeInsets.all(12),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 8,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                            itemCount: _emojis.length,
                            itemBuilder: (context, index) {
                              final emoji = _emojis[index];
                              return SpringTap(
                                onTap: () => _insertEmoji(emoji),
                                child: Center(
                                  child: Text(
                                    emoji,
                                    style: const TextStyle(fontSize: 22),
                                  ),
                                ),
                              );
                            },
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
    );
  }
}

class GifPickerSheet extends StatefulWidget {
  final Function(String) onGifSelected;
  const GifPickerSheet({super.key, required this.onGifSelected});

  @override
  State<GifPickerSheet> createState() => _GifPickerSheetState();
}

class _GifPickerSheetState extends State<GifPickerSheet> {
  final _searchController = TextEditingController();
  List<String> _gifs = [];
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchGifs('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchGifs(String query) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      String apiKey = 'dc6zaTOxFJmzC'; // Default beta testing key
      try {
        final doc = await FirebaseFirestore.instance.collection('metadata').doc('app_config').get();
        if (doc.exists && doc.data() != null) {
          String? dbKey = doc.data()!['giphyApiKey'] as String?;
          if (dbKey == null || dbKey.isEmpty) {
            dbKey = doc.data()!['giphyApiKEy'] as String?;
          }
          if (dbKey != null && dbKey.isNotEmpty) {
            apiKey = dbKey;
          }
        }
      } catch (_) {}

      final url = query.isEmpty
          ? 'https://api.giphy.com/v1/gifs/trending?api_key=$apiKey&limit=15'
          : 'https://api.giphy.com/v1/gifs/search?api_key=$apiKey&q=${Uri.encodeComponent(query)}&limit=15';

      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> results = data['data'] ?? [];
        if (mounted) {
          setState(() {
            _gifs = results.map<String>((gif) {
              return gif['images']['fixed_height_small']['url'] as String;
            }).toList();
          });
        }
      } else {
        setState(() {
          _errorMessage = apiKey == 'dc6zaTOxFJmzC'
              ? 'GIPHY API rate limit reached.\n\nTo resolve this, add your own Giphy API Key in Firestore metadata/app_config document under "giphyApiKey" (or "giphyApiKEy").'
              : 'GIPHY API error. Please check your custom Giphy API Key configuration in Firestore.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Network connection issue. Please check your internet connection.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppTheme.surfaceLight, width: 1),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Header Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search GIPHY',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          _fetchGifs('');
                        },
                      )
                    : null,
              ),
              onSubmitted: (val) => _fetchGifs(val.trim()),
            ),
          ),
          const SizedBox(height: 12),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage.isNotEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Text(
                            _errorMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppTheme.textSecondary),
                          ),
                        ),
                      )
                    : _gifs.isEmpty
                        ? const Center(child: Text('No GIFs found'))
                        : GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                            itemCount: _gifs.length,
                            itemBuilder: (context, index) {
                              final gifUrl = _gifs[index];
                              return GestureDetector(
                                onTap: () {
                                  widget.onGifSelected(gifUrl);
                                  Navigator.pop(context);
                                },
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(
                                    gifUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.error),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
