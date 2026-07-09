import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:secure_chat/config/theme.dart';
import 'package:secure_chat/services/story_service.dart';
import 'package:secure_chat/services/storage_service.dart';
import 'package:secure_chat/screens/settings_screen.dart'; // SpringTap

class StoryEditorScreen extends StatefulWidget {
  const StoryEditorScreen({super.key});

  @override
  State<StoryEditorScreen> createState() => _StoryEditorScreenState();
}

class _StoryEditorScreenState extends State<StoryEditorScreen> {
  final _storyService = StoryService();
  final _storageService = StorageService();
  final _captionController = TextEditingController();

  File? _imageFile;
  String? _imageSource; // 'camera' or 'gallery'
  bool _isTextMode = false;
  bool _isUploading = false;
  bool _showCaptionInput = false;
  int _selectedGradient = 0;

  static const List<List<Color>> _gradients = [
    [Color(0xFF667eea), Color(0xFF764ba2)],
    [Color(0xFFf857a6), Color(0xFFff5858)],
    [Color(0xFF00c6ff), Color(0xFF0072ff)],
    [Color(0xFFf7971e), Color(0xFFffd200)],
    [Color(0xFF11998e), Color(0xFF38ef7d)],
    [Color(0xFFFC5C7D), Color(0xFF6A82FB)],
    [Color(0xFF1a1a2e), Color(0xFF16213e)],
    [Color(0xFFe1eec3), Color(0xFFf05053)],
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_imageFile == null && !_isTextMode) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null) {
        final source = args['source'] as String?;
        if (source == 'text') {
          setState(() => _isTextMode = true);
        } else {
          _pickImage(source == 'gallery' ? ImageSource.gallery : ImageSource.camera);
        }
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    String? filePath;
    if (Platform.isWindows) {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null && result.files.single.path != null) {
        filePath = result.files.single.path;
      }
    } else {
      final pickedFile = await ImagePicker().pickImage(
        source: source,
        imageQuality: 40,
        maxWidth: 600,
      );
      if (pickedFile != null) {
        filePath = pickedFile.path;
      }
    }

    if (filePath == null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    setState(() {
      _imageFile = File(filePath!);
      _imageSource = Platform.isWindows ? 'gallery' : (source == ImageSource.camera ? 'camera' : 'gallery');
    });
  }

  Future<void> _publishStory() async {
    setState(() => _isUploading = true);
    try {
      if (_isTextMode) {
        final text = _captionController.text.trim();
        if (text.isEmpty) return;
        await _storyService.createStory(
          text,
          _selectedGradient,
          mediaType: 'text',
        );
      } else if (_imageFile != null) {
        final base64Url = await _storageService.uploadStoryMedia(_imageFile!, true);
        final caption = _captionController.text.trim();
        await _storyService.createStory(
          '',
          0,
          mediaUrl: base64Url,
          mediaType: 'image',
          captionText: caption.isNotEmpty ? caption : null,
        );
      }
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to post story: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isTextMode && _imageFile == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background
          if (_isTextMode)
            _buildTextStoryBackground()
          else
            _buildImagePreview(),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                    ),
                    const Spacer(),
                    if (!_isTextMode)
                      IconButton(
                        onPressed: () {
                          setState(() => _showCaptionInput = !_showCaptionInput);
                        },
                        icon: Icon(
                          _showCaptionInput ? Icons.text_fields_rounded : Icons.text_fields_rounded,
                          color: _showCaptionInput ? AppTheme.accentPrimary : Colors.white,
                          size: 26,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Caption input overlay for image mode
          if (!_isTextMode && _showCaptionInput)
            Positioned(
              left: 0,
              right: 0,
              bottom: 100,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(150),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: TextField(
                  controller: _captionController,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Inter',
                    fontSize: 16,
                  ),
                  maxLines: 3,
                  maxLength: 150,
                  decoration: const InputDecoration(
                    hintText: 'Add a caption...',
                    hintStyle: TextStyle(color: Colors.white54),
                    border: InputBorder.none,
                    counterStyle: TextStyle(color: Colors.white38),
                  ),
                ),
              ),
            ),

          // Bottom bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Row(
                  children: [
                    if (_isTextMode)
                      // Gradient selector
                      SizedBox(
                        height: 32,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          shrinkWrap: true,
                          itemCount: _gradients.length,
                          itemBuilder: (context, index) {
                            return GestureDetector(
                              onTap: () => setState(() => _selectedGradient = index),
                              child: Container(
                                width: 32,
                                height: 32,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(colors: _gradients[index]),
                                  border: Border.all(
                                    color: _selectedGradient == index ? Colors.white : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    const Spacer(),
                    SpringTap(
                      onTap: _isUploading ? null : _publishStory,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppTheme.accentPrimary, AppTheme.accentSecondary],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.accentPrimary.withAlpha(80),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: _isUploading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.send_rounded, color: Colors.white, size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    'Share',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
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

          // Upload overlay
          if (_isUploading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppTheme.accentPrimary),
                    SizedBox(height: 16),
                    Text(
                      'Sharing your story...',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    return Image.file(
      _imageFile!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
  }

  Widget _buildTextStoryBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _gradients[_selectedGradient],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: TextField(
            controller: _captionController,
            textAlign: TextAlign.center,
            maxLines: 5,
            maxLength: 200,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.4,
              shadows: [
                Shadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
              ],
            ),
            decoration: const InputDecoration(
              hintText: 'Type your story...',
              hintStyle: TextStyle(
                color: Colors.white54,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
              border: InputBorder.none,
              counterStyle: TextStyle(color: Colors.white38),
            ),
          ),
        ),
      ),
    );
  }
}
