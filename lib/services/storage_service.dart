import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

class StorageService {
  Future<String> _uploadToCloudinary(File file) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('metadata').doc('app_config').get();
      if (!doc.exists) {
        throw Exception("Firestore metadata/app_config document not found.");
      }

      final cloudName = doc.data()?['cloudinaryCloudName'] as String? ?? '';
      final uploadPreset = doc.data()?['cloudinaryUploadPreset'] as String? ?? '';

      if (cloudName.isEmpty || uploadPreset.isEmpty) {
        throw Exception("Cloudinary configuration (cloudinaryCloudName, cloudinaryUploadPreset) is missing in Firestore metadata/app_config.");
      }

      // Construct Cloudinary upload endpoint (using 'auto' resource type to handle images and videos)
      final uploadUrl = 'https://api.cloudinary.com/v1_1/$cloudName/auto/upload';

      final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
      request.fields['upload_preset'] = uploadPreset;
      request.files.add(await http.MultipartFile.fromPath('file', file.path));

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final publicUrl = data['secure_url'] as String?;
        if (publicUrl != null && publicUrl.isNotEmpty) {
          print("Successfully uploaded to Cloudinary: $publicUrl");
          return publicUrl;
        }
        throw Exception("Cloudinary response did not contain secure_url: ${response.body}");
      } else {
        throw Exception("Cloudinary upload failed with status ${response.statusCode}: ${response.body}");
      }
    } catch (e) {
      print("Cloudinary Upload Error: $e");
      rethrow;
    }
  }

  Future<String> uploadStoryMedia(File file, bool isImage) async {
    return _uploadToCloudinary(file);
  }

  Future<String> uploadMessageMedia(File file, String contentType) async {
    return _uploadToCloudinary(file);
  }
}
