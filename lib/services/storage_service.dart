import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

class StorageService {
  Future<String> _uploadToCloudflare(File file) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('metadata').doc('app_config').get();
      final uploadUrl = doc.exists ? (doc.data()?['cloudflareUploadUrl'] as String? ?? '') : '';

      if (uploadUrl.isEmpty) {
        throw Exception("Cloudflare R2 upload gateway URL is not configured in Firestore metadata/app_config.");
      }

      final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
      request.files.add(await http.MultipartFile.fromPath('file', file.path));

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final downloadUrl = response.body.trim();
        if (downloadUrl.startsWith('http://') || downloadUrl.startsWith('https://')) {
          print("Successfully uploaded to Cloudflare R2: $downloadUrl");
          return downloadUrl;
        }
        throw Exception("Invalid upload gateway response format: $downloadUrl");
      } else {
        throw Exception("Cloudflare gateway returned error code: ${response.statusCode}");
      }
    } catch (e) {
      print("Cloudflare R2 Upload Error: $e");
      rethrow;
    }
  }

  Future<String> uploadStoryMedia(File file, bool isImage) async {
    return _uploadToCloudflare(file);
  }

  Future<String> uploadMessageMedia(File file, String contentType) async {
    return _uploadToCloudflare(file);
  }
}
