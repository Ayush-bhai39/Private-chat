import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

class StorageService {
  Future<String> _uploadToSupabase(File file, String contentType) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('metadata').doc('app_config').get();
      if (!doc.exists) {
        throw Exception("Firestore metadata/app_config document not found.");
      }

      final supabaseUrl = doc.data()?['supabaseUrl'] as String? ?? '';
      final supabaseAnonKey = doc.data()?['supabaseAnonKey'] as String? ?? '';
      final supabaseBucket = doc.data()?['supabaseBucket'] as String? ?? 'secure-chat-media';

      if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
        throw Exception("Supabase configuration (supabaseUrl, supabaseAnonKey) is missing in Firestore metadata/app_config.");
      }

      // Clean trailing slash from URL if present
      final cleanUrl = supabaseUrl.endsWith('/') 
          ? supabaseUrl.substring(0, supabaseUrl.length - 1) 
          : supabaseUrl;

      // Generate a unique filename using UUID
      final originalName = file.path.split(Platform.pathSeparator).last;
      final fileExt = originalName.split('.').last;
      final randomId = const Uuid().v4();
      final filename = '${DateTime.now().millisecondsSinceEpoch}_$randomId.$fileExt';
      final filePath = 'media/$filename';

      // Construct REST upload URL
      final uploadUrl = '$cleanUrl/storage/v1/object/$supabaseBucket/$filePath';

      final bytes = await file.readAsBytes();

      final response = await http.post(
        Uri.parse(uploadUrl),
        headers: {
          'Authorization': 'Bearer $supabaseAnonKey',
          'apikey': '$supabaseAnonKey',
          'Content-Type': contentType,
        },
        body: bytes,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        // Construct the public URL to access the uploaded file
        final publicUrl = '$cleanUrl/storage/v1/object/public/$supabaseBucket/$filePath';
        print("Successfully uploaded to Supabase Storage: $publicUrl");
        return publicUrl;
      } else {
        throw Exception("Supabase upload failed with status ${response.statusCode}: ${response.body}");
      }
    } catch (e) {
      print("Supabase Upload Error: $e");
      rethrow;
    }
  }

  Future<String> uploadStoryMedia(File file, bool isImage) async {
    final contentType = isImage ? 'image/jpeg' : 'video/mp4';
    return _uploadToSupabase(file, contentType);
  }

  Future<String> uploadMessageMedia(File file, String contentType) async {
    return _uploadToSupabase(file, contentType);
  }
}
