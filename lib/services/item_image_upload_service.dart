import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class ItemImageUploadService {
  ItemImageUploadService._();

  static final ItemImageUploadService instance = ItemImageUploadService._();
  static const _uuid = Uuid();
  static const _cloudName = 'dm5umqb7z';
  static const _uploadPreset = String.fromEnvironment(
    'CLOUDINARY_ITEM_UPLOAD_PRESET',
    defaultValue: 'profile_upload',
  );

  Future<String> pickCompressAndUpload() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) {
      throw const _UserCancelledException();
    }

    final compressed = await _compressImage(picked);
    final fileName = '${_uuid.v4()}.jpg';

    final imageUrl = await _uploadToCloudinary(
      bytes: compressed,
      fileName: fileName,
    );
    return imageUrl;
  }

  Future<Uint8List> _compressImage(XFile picked) async {
    final originalBytes = await picked.readAsBytes();
    final ext = p.extension(picked.name).toLowerCase();
    final format = ext == '.png' ? CompressFormat.png : CompressFormat.jpeg;
    final result = await FlutterImageCompress.compressWithList(
      originalBytes,
      quality: 75,
      minWidth: 1280,
      minHeight: 1280,
      format: format,
    );
    if (result.isEmpty) {
      throw Exception('Failed to compress image.');
    }
    return result;
  }

  Future<String> _uploadToCloudinary({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final presetsToTry = <String>{
      _uploadPreset.trim(),
      'profile_upload',
      'ml_default',
    }.where((e) => e.isNotEmpty).toList();

    String? lastError;
    for (final preset in presetsToTry) {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload'),
      );
      request.fields['upload_preset'] = preset;
      request.fields['folder'] = 'items/images';
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      final body = (jsonDecode(response.body) as Map<String, dynamic>?) ?? const {};
      if (streamedResponse.statusCode >= 200 && streamedResponse.statusCode < 300) {
        final secureUrl = (body['secure_url'] as String?)?.trim();
        if (secureUrl != null && secureUrl.isNotEmpty) {
          return secureUrl;
        }
        lastError = 'Cloudinary response missing secure_url.';
        continue;
      }

      lastError =
          'preset "$preset": ${_extractCloudinaryError(responseBody: response.body, body: body)}';
    }

    throw Exception(
      'Cloudinary upload failed. Tried presets: ${presetsToTry.join(', ')}. '
      '${lastError ?? ''}',
    );
  }

  String _extractCloudinaryError({
    required String responseBody,
    required Map<String, dynamic> body,
  }) {
    final error = body['error'];
    if (error is Map && error['message'] != null) {
      return '${error['message']}';
    }
    if (error != null) return '$error';
    if (responseBody.trim().isNotEmpty) return responseBody;
    return 'Unknown Cloudinary error.';
  }
}

class _UserCancelledException implements Exception {
  const _UserCancelledException();
}
