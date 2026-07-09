import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:secure_chat/config/theme.dart';
import 'package:secure_chat/models/message_model.dart';
import 'package:secure_chat/services/chat_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

class MessageBubble extends StatefulWidget {
  final MessageModel message;
  final String text;
  final bool isMine;
  final String? repliedText;

  const MessageBubble({
    super.key,
    required this.message,
    required this.text,
    required this.isMine,
    this.repliedText,
  });

  String _getFileName(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      final segments = path.split('/');
      if (segments.isNotEmpty) {
        final rawName = Uri.decodeComponent(segments.last);
        if (rawName.contains('_')) {
          return rawName.substring(rawName.indexOf('_') + 1);
        }
        return rawName;
      }
    } catch (_) {}
    return 'Document';
  }

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _isDownloading = false;
  String? _localPath;
  http.Client? _activeClient;

  @override
  void initState() {
    super.initState();
    _checkLocalFileExists();
  }

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id || oldWidget.message.mediaUrl != widget.message.mediaUrl) {
      _checkLocalFileExists();
    }
  }

  Future<void> _checkLocalFileExists() async {
    if (widget.message.mediaUrl == null) return;
    final tempDir = Directory.systemTemp;

    // Check if the marker file exists
    final markerFile = File('${tempDir.path}/${widget.message.id}.marker');
    if (await markerFile.exists()) {
      try {
        final publicPath = (await markerFile.readAsString()).trim();
        final publicFile = File(publicPath);
        if (await publicFile.exists()) {
          if (mounted) {
            setState(() {
              _localPath = publicPath;
            });
          }
          return;
        } else {
          // File was deleted from public storage, clean up marker
          await markerFile.delete();
        }
      } catch (_) {}
    }

    // Fallback: check if the old cache format file still exists
    final filename = widget._getFileName(widget.message.mediaUrl!);
    final oldFile = File('${tempDir.path}/${widget.message.id}_$filename');
    if (await oldFile.exists()) {
      if (mounted) {
        setState(() {
          _localPath = oldFile.path;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _localPath = null;
      });
    }
  }

  Future<String> _getUniqueFilePath(String folderPath, String filename) async {
    var file = File('$folderPath/$filename');
    if (!await file.exists()) {
      return file.path;
    }

    final dotIndex = filename.lastIndexOf('.');
    final baseName = dotIndex != -1 ? filename.substring(0, dotIndex) : filename;
    final ext = dotIndex != -1 ? filename.substring(dotIndex) : '';

    int counter = 1;
    while (true) {
      final newPath = '$folderPath/${baseName}_$counter$ext';
      file = File(newPath);
      if (!await file.exists()) {
        return newPath;
      }
      counter++;
      if (counter > 1000) {
        return '$folderPath/${baseName}_${DateTime.now().millisecondsSinceEpoch}$ext';
      }
    }
  }

  Future<String> _getPublicDownloadPath(String filename, String mediaType, String messageId) async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final appDocDir = await getApplicationDocumentsDirectory();
        final folderPath = '${appDocDir.path}/SecretChat';
        final dir = Directory(folderPath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return await _getUniqueFilePath(folderPath, filename);
      } catch (e) {
        print("Failed to use documents storage, falling back to temp: $e");
        final tempDir = Directory.systemTemp;
        return '${tempDir.path}/${messageId}_$filename';
      }
    } else if (Platform.isWindows) {
      try {
        final downloadsDir = await getDownloadsDirectory();
        final folderPath = downloadsDir != null ? '${downloadsDir.path}\\SecretChat' : '${Directory.systemTemp.path}/SecretChat';
        final dir = Directory(folderPath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return await _getUniqueFilePath(folderPath, filename);
      } catch (e) {
        print("Failed to use downloads storage, falling back to temp: $e");
        final tempDir = Directory.systemTemp;
        return '${tempDir.path}/${messageId}_$filename';
      }
    } else {
      final tempDir = Directory.systemTemp;
      return '${tempDir.path}/${messageId}_$filename';
    }
  }

  Future<void> _startDownload() async {
    if (widget.message.mediaUrl == null) return;
    setState(() {
      _isDownloading = true;
    });

    try {
      final client = http.Client();
      _activeClient = client;
      
      http.Response response;
      int retries = 0;
      while (true) {
        response = await client.get(Uri.parse(widget.message.mediaUrl!));
        if (response.statusCode == 200) {
          break;
        } else if (response.statusCode == 404 && retries < 4) {
          retries++;
          // Exponential backoff retry: wait 1.5s, 3s, 4.5s...
          await Future.delayed(Duration(milliseconds: 1500 * retries));
        } else {
          throw Exception("Server returned code ${response.statusCode}");
        }
      }

      final encryptedBytes = response.bodyBytes;
      final chatService = ChatService();
      final decryptedBytes = await chatService.decryptMessageFileBytes(widget.message, encryptedBytes);

        final filename = widget._getFileName(widget.message.mediaUrl!);
        final publicPath = await _getPublicDownloadPath(filename, widget.message.mediaType ?? 'file', widget.message.id);
        final file = File(publicPath);
        await file.writeAsBytes(decryptedBytes);

        // Write marker file in cache directory so the app knows it is downloaded even if E2EE message expires
        final tempDir = Directory.systemTemp;
        final markerFile = File('${tempDir.path}/${widget.message.id}.marker');
        await markerFile.writeAsString(publicPath);

        if (mounted) {
          setState(() {
            _localPath = publicPath;
            _isDownloading = false;
            _activeClient = null;
          });

          final isPublic = !publicPath.contains(tempDir.path);
          String successMsg = 'File downloaded successfully';
          if (isPublic) {
            if (Platform.isAndroid || Platform.isIOS) {
              successMsg = 'Saved to App Documents/SecretChat';
            } else {
              final folderName = widget.message.mediaType == 'image'
                  ? 'Pictures/SecretChat'
                  : (widget.message.mediaType == 'video' ? 'Movies/SecretChat' : 'Download/SecretChat');
              successMsg = 'Saved to $folderName';
            }
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(successMsg),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppTheme.success,
            ),
          );
        }
      } catch (e) {
      print("Download/decryption error: $e");
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _activeClient = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    }
  }

  void _cancelDownload() {
    if (_activeClient != null) {
      _activeClient?.close();
      setState(() {
        _activeClient = null;
        _isDownloading = false;
      });
    }
  }

  Future<void> _openFile() async {
    if (_localPath == null) return;
    try {
      final result = await OpenFilex.open(_localPath!);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: ${result.message}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening file: $e')),
      );
    }
  }

  Widget _buildStatusIcon() {
    final status = widget.message.status;
    final isPending = widget.message.hasPendingWrites;

    if (isPending) {
      return Icon(
        Icons.access_time_rounded,
        size: 11,
        color: Colors.white.withOpacity(0.5),
      );
    }

    switch (status) {
      case 'seen':
        return const Icon(
          Icons.done_all_rounded,
          size: 14,
          color: Color(0xFF38BDF8), // Premium sky-blue seen tick
        );
      case 'delivered':
        return Icon(
          Icons.done_all_rounded,
          size: 14,
          color: Colors.white.withOpacity(0.65),
        );
      case 'sent':
      default:
        return Icon(
          Icons.done_rounded,
          size: 14,
          color: Colors.white.withOpacity(0.5),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final format = DateFormat('HH:mm');
    final timeString = format.format(widget.message.timestamp);
    final showDeleted = widget.message.isDeleted;
    final displayText = showDeleted ? '🚫 This message was deleted' : widget.text;

    // Reactions calculations
    final hasReactions = widget.message.reactions.isNotEmpty;
    final uniqueReactions = widget.message.reactions.values.toSet().toList();

    return Align(
      alignment: widget.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Main Bubble Container
            GestureDetector(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                decoration: BoxDecoration(
                  gradient: widget.isMine
                      ? const LinearGradient(
                          colors: [AppTheme.accentPrimary, AppTheme.accentSecondary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : LinearGradient(
                          colors: [
                            AppTheme.surfaceLight.withOpacity(0.4),
                            AppTheme.surfaceLight.withOpacity(0.2),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: widget.isMine ? const Radius.circular(16) : const Radius.circular(0),
                    bottomRight: widget.isMine ? const Radius.circular(0) : const Radius.circular(16),
                  ),
                  border: Border.all(
                    color: widget.isMine
                        ? AppTheme.accentPrimary.withOpacity(0.5)
                        : AppTheme.surfaceLight.withOpacity(0.4),
                    width: 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: IntrinsicWidth(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Quoted reply indicator panel (if present)
                          if (widget.message.repliedMessageId != null && widget.repliedText != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border(
                                  left: BorderSide(
                                    color: widget.isMine ? Colors.white : AppTheme.accentPrimary,
                                    width: 3.5,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.message.repliedMessageSenderName ?? 'Replied Message',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: widget.isMine ? Colors.white70 : AppTheme.accentPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.repliedText!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 12,
                                      color: widget.isMine ? Colors.white.withOpacity(0.9) : Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // Render E2EE Media/File layouts
                          if (!showDeleted && widget.message.mediaUrl != null) ...[
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: _localPath != null
                                  ? _buildDecryptedMedia()
                                  : _buildEncryptedPlaceholder(),
                            ),
                          ],

                          // Text Body
                          Text(
                            displayText,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 15,
                              color: showDeleted ? AppTheme.textSecondary : Colors.white,
                              fontStyle: showDeleted ? FontStyle.italic : FontStyle.normal,
                            ),
                          ),
                          const SizedBox(height: 4),

                          // Timestamp Row
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.message.isEdited && !showDeleted) ...[
                                  const Text(
                                    'Edited • ',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 9,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                                Text(
                                  timeString,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 10,
                                    color: showDeleted
                                        ? AppTheme.textSecondary
                                        : Colors.white.withOpacity(0.6),
                                  ),
                                ),
                                if (widget.isMine && !showDeleted) ...[
                                  const SizedBox(width: 4),
                                  _buildStatusIcon(),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Mini floating reactions badge
            if (hasReactions)
              Positioned(
                bottom: -12,
                right: widget.isMine ? 12 : null,
                left: widget.isMine ? null : 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.black, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        uniqueReactions.join(' '),
                        style: const TextStyle(fontSize: 11),
                      ),
                      if (widget.message.reactions.length > 1) ...[
                        const SizedBox(width: 4),
                        Text(
                          widget.message.reactions.length.toString(),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Decrypted, fully downloaded state renderers
  Widget _buildDecryptedMedia() {
    final type = widget.message.mediaType;

    if (type == 'gif' || type == 'image') {
      return GestureDetector(
        onTap: _openFile,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            File(_localPath!),
            fit: BoxFit.cover,
            width: 200,
            height: 200,
            cacheWidth: 400, // Memory footprint downscale optimization for budget Android devices
            errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image_rounded),
          ),
        ),
      );
    } else if (type == 'video') {
      return GestureDetector(
        onTap: _openFile,
        child: Container(
          width: 200,
          height: 120,
          decoration: BoxDecoration(
            color: Colors.black45,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: const Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.play_circle_filled_rounded, size: 48, color: Colors.white),
              Positioned(
                bottom: 8,
                child: Text(
                  'Video • Tap to Play',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // File/Document
      return GestureDetector(
        onTap: _openFile,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.accentPrimary.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.insert_drive_file_rounded, color: AppTheme.accentPrimary, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      widget._getFileName(widget.message.mediaUrl!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Open file',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppTheme.textSecondary),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              const Icon(Icons.open_in_new_rounded, color: Colors.white54, size: 16),
            ],
          ),
        ),
      );
    }
  }

  // Encrypted, not-yet-downloaded/downloading state placeholder
  Widget _buildEncryptedPlaceholder() {
    final type = widget.message.mediaType;
    final isFile = type == 'file';
    
    // Check if the file is currently uploading
    final isUploading = widget.message.status == 'uploading' || widget.message.mediaUrl == 'uploading';

    if (isUploading) {
      final isMine = widget.isMine;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 200,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.accentPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isMine ? 'Uploading media...' : 'Waiting for media...',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // 24 Hour disappearing checks
    final timePassed = DateTime.now().difference(widget.message.timestamp);
    final isExpired = timePassed.inHours >= 24;
    final hoursRemaining = 24 - timePassed.inHours;
    final minutesRemaining = 60 - (timePassed.inMinutes % 60);

    if (isExpired) {
      return _buildExpiredPlaceholder();
    }

    if (isFile) {
      final filename = widget._getFileName(widget.message.mediaUrl!);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.white10,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.insert_drive_file_outlined, color: Colors.white60, size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        filename,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: Colors.white70),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'E2EE File',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppTheme.textSecondary),
                ),
              ],
            ),
            const SizedBox(width: 8),
            _buildDownloadButton(),
          ],
        ),
      ),
      _buildDisappearingWarning(hoursRemaining, minutesRemaining),
    ],
      );
    }

    // Image/Video placeholder box
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 200,
          height: 150,
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                type == 'video' ? Icons.videocam_rounded : Icons.image_rounded,
                size: 48,
                color: Colors.white12,
              ),
              _buildDownloadButton(),
              Positioned(
                bottom: 8,
                child: Text(
                  type == 'video' ? 'Video • Encrypted' : 'Photo • Encrypted',
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 10, color: Colors.white38),
                ),
              ),
            ],
          ),
        ),
        _buildDisappearingWarning(hoursRemaining, minutesRemaining),
      ],
    );
  }

  Widget _buildExpiredPlaceholder() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_off_rounded, color: AppTheme.error.withOpacity(0.7), size: 20),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Media Expired',
                style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white54),
              ),
              SizedBox(height: 2),
              Text(
                '24-hour limit reached',
                style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDisappearingWarning(int hoursRemaining, int minutesRemaining) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 12),
          const SizedBox(width: 6),
          Text(
            hoursRemaining > 1 
                ? 'Expires in $hoursRemaining hours. Download to save.' 
                : 'Expires in $minutesRemaining min. Download to save.',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              color: Colors.amber,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // Combined Download & Cancel download button
  Widget _buildDownloadButton() {
    return GestureDetector(
      onTap: _isDownloading ? _cancelDownload : _startDownload,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_isDownloading) ...[
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.accentPrimary,
                ),
              ),
              const Icon(
                Icons.close_rounded,
                size: 14,
                color: Colors.white,
              ),
            ] else ...[
              const Icon(
                Icons.download_rounded,
                size: 18,
                color: Colors.white,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
