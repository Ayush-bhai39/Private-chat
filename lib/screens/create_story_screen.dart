import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:secure_chat/config/theme.dart';
import 'package:secure_chat/services/story_service.dart';
import 'package:secure_chat/services/note_service.dart';
import 'package:secure_chat/services/storage_service.dart';
import 'package:secure_chat/widgets/gradient_picker.dart';

class CreateStoryScreen extends StatefulWidget {
  const CreateStoryScreen({super.key});

  @override
  State<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends State<CreateStoryScreen> {
  final _storyController = TextEditingController();
  final _noteController = TextEditingController();
  final _storyService = StoryService();
  final _noteService = NoteService();
  final _storageService = StorageService();
  final _imagePicker = ImagePicker();

  int _selectedGradientIndex = 0;
  bool _isSharing = false;
  File? _selectedImage;

  Future<void> _pickImage(ImageSource source) async {
    try {
      String? filePath;
      if (Platform.isWindows) {
        final result = await FilePicker.platform.pickFiles(type: FileType.image);
        if (result != null && result.files.single.path != null) {
          filePath = result.files.single.path;
        }
      } else {
        final pickedFile = await _imagePicker.pickImage(
          source: source,
          imageQuality: 40,
          maxWidth: 600,
        );
        if (pickedFile != null) {
          filePath = pickedFile.path;
        }
      }
      if (filePath != null) {
        setState(() {
          _selectedImage = File(filePath!);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking image: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  Future<void> _shareStory() async {
    final text = _storyController.text.trim();
    if (text.isEmpty && _selectedImage == null) return;
    if (_isSharing) return;

    setState(() => _isSharing = true);

    try {
      String? mediaUrl;
      String mediaType = 'text';

      if (_selectedImage != null) {
        mediaUrl = await _storageService.uploadStoryMedia(_selectedImage!, true);
        mediaType = 'image';
      }

      await _storyService.createStory(
        text,
        _selectedGradientIndex,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share story: ${e.toString()}'),
            backgroundColor: Colors.red.shade800,
          ),
        );
        setState(() => _isSharing = false);
      }
    }
  }

  Future<void> _shareNote() async {
    final text = _noteController.text.trim();
    if (text.isEmpty || _isSharing) return;

    setState(() => _isSharing = true);

    try {
      await _noteService.createOrUpdateNote(text);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share note: ${e.toString()}'),
            backgroundColor: Colors.red.shade800,
          ),
        );
        setState(() => _isSharing = false);
      }
    }
  }

  @override
  void dispose() {
    _storyController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storyGradient = AppTheme.storyGradients[_selectedGradientIndex];

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text(
            'Create Post',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold),
          ),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Story'),
              Tab(text: 'Note'),
            ],
          ),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            // Story Creator Tab
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: _selectedImage != null
                  ? null
                  : BoxDecoration(
                      gradient: LinearGradient(
                        colors: storyGradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
              child: Stack(
                children: [
                  // Selected image background
                  if (_selectedImage != null)
                    Positioned.fill(
                      child: Image.file(
                        _selectedImage!,
                        fit: BoxFit.cover,
                      ),
                    ),

                  // Overlay Content
                  Column(
                    children: [
                      // Header tools
                      if (_selectedImage != null)
                        Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: CircleAvatar(
                              backgroundColor: Colors.black45,
                              child: IconButton(
                                icon: const Icon(Icons.close, color: Colors.white),
                                onPressed: () {
                                  setState(() {
                                    _selectedImage = null;
                                  });
                                },
                              ),
                            ),
                          ),
                        ),

                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 40),
                            child: TextField(
                              controller: _storyController,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: Colors.black45,
                                    blurRadius: 10,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                              maxLines: null,
                              cursorColor: Colors.white,
                              decoration: InputDecoration(
                                hintText: _selectedImage != null
                                    ? 'Add a caption...'
                                    : 'Type your story...',
                                hintStyle: TextStyle(
                                  fontFamily: 'Inter',
                                  color: Colors.white.withOpacity(0.6),
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Bottom tools for story
                      Container(
                        color: AppTheme.surface.withOpacity(0.85),
                        padding: const EdgeInsets.all(16),
                        child: SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Media Pickers
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.photo_library_rounded, size: 28),
                                    onPressed: () => _pickImage(ImageSource.gallery),
                                    tooltip: 'Gallery',
                                  ),
                                  const SizedBox(width: 24),
                                  IconButton(
                                    icon: const Icon(Icons.camera_alt_rounded, size: 28),
                                    onPressed: () => _pickImage(ImageSource.camera),
                                    tooltip: 'Camera',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              if (_selectedImage == null) ...[
                                GradientPicker(
                                  selectedIndex: _selectedGradientIndex,
                                  onSelected: (index) {
                                    setState(() => _selectedGradientIndex = index);
                                  },
                                ),
                                const SizedBox(height: 12),
                              ],

                              ElevatedButton(
                                onPressed: _isSharing ? null : _shareStory,
                                child: _isSharing
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                      )
                                    : const Text('Share Story'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Note Creator Tab
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Share a thought',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Notes are short status messages that appear for 24h.',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: AppTheme.textSecondary.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _noteController,
                    maxLength: 60,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'What\'s on your mind? (Max 60 characters)',
                    ),
                  ),
                  const Spacer(),
                  SafeArea(
                    child: ElevatedButton(
                      onPressed: _isSharing ? null : _shareNote,
                      child: _isSharing
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Share Note'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
