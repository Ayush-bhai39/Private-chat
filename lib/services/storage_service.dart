import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<String> uploadStoryMedia(File file, bool isImage) async {
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.path.split(Platform.pathSeparator).last}';

    // 1. Try Litterbox first (extremely reliable, fast, keyless, auto-expires in 24 hours)
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://litterbox.catbox.moe/resources/internals/api.php'),
      );
      request.fields['reqtype'] = 'fileupload';
      request.fields['time'] = '24h';
      request.files.add(await http.MultipartFile.fromPath(
        'fileToUpload',
        file.path,
      ));

      final streamedResponse = await request.send().timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final downloadUrl = response.body.trim();
        if (downloadUrl.startsWith('https://')) {
          print("Uploaded successfully to Litterbox: $downloadUrl");
          return downloadUrl;
        }
      }
      print("Litterbox upload failed with status: ${response.statusCode}");
    } catch (e) {
      print("Litterbox upload failed: $e. Trying Firebase Storage...");
    }

    // 2. Try Firebase Storage (native backup)
    try {
      final ref = _storage.ref().child('stories/$fileName');
      final uploadTask = await ref.putFile(
        file,
        SettableMetadata(contentType: isImage ? 'image/jpeg' : 'video/mp4'),
      );
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      print("Uploaded successfully to Firebase Storage: $downloadUrl");
      return downloadUrl;
    } catch (e) {
      print("Firebase Storage upload failed: $e. Trying ImgBB...");
    }

    // 3. Try ImgBB (legacy backup)
    try {
      final bytes = await file.readAsBytes();
      final base64Image = base64Encode(bytes);

      final doc = await FirebaseFirestore.instance.collection('metadata').doc('app_config').get();
      final apiKey = doc.exists ? (doc.data()?['imgbbApiKey'] as String? ?? '') : '';

      if (apiKey.isNotEmpty && isImage) {
        final response = await http.post(
          Uri.parse('https://api.imgbb.com/1/upload'),
          body: {
            'key': apiKey,
            'image': base64Image,
          },
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          print("Uploaded successfully to ImgBB");
          return data['data']['url'] as String;
        } else {
          print("ImgBB failed with status: ${response.statusCode}");
        }
      }
    } catch (e) {
      print("ImgBB upload failed: $e");
    }

    // 4. Final Fallback: Base64 data URI (guarantees upload never crashes the app)
    try {
      final bytes = await file.readAsBytes();
      final base64Str = base64Encode(bytes);
      final format = isImage ? 'jpeg' : 'mp4';
      print("Falling back to Base64 URI representation");
      return 'data:image/$format;base64,$base64Str';
    } catch (e) {
      print("Base64 fallback failed: $e");
      rethrow;
    }
  }

  Future<String> uploadMessageMedia(File file, String contentType) async {
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.path.split(Platform.pathSeparator).last}';

    // 1. Try Litterbox (expires in 24 hours, perfect for security and auto-deletion)
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://litterbox.catbox.moe/resources/internals/api.php'),
      );
      request.fields['reqtype'] = 'fileupload';
      request.fields['time'] = '24h';
      request.files.add(await http.MultipartFile.fromPath('fileToUpload', file.path));

      final streamedResponse = await request.send().timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final downloadUrl = response.body.trim();
        if (downloadUrl.startsWith('https://')) {
          print("Media uploaded successfully to Litterbox: $downloadUrl");
          return downloadUrl;
        }
      }
    } catch (e) {
      print("Litterbox media upload failed: $e");
    }

    // 2. Try Firebase Storage
    try {
      final ref = _storage.ref().child('media/$fileName');
      final uploadTask = await ref.putFile(
        file,
        SettableMetadata(contentType: contentType),
      );
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      print("Media uploaded successfully to Firebase Storage: $downloadUrl");
      return downloadUrl;
    } catch (e) {
      print("Firebase Storage media upload failed: $e");
    }

    // 3. Fallback: Base64 URI
    final bytes = await file.readAsBytes();
    final base64Str = base64Encode(bytes);
    return 'data:$contentType;base64,$base64Str';
  }
}
