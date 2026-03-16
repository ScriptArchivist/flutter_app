import 'package:dio/dio.dart';

import '../config/app_config.dart';

class UploadRepository {
  final Dio dio;

  UploadRepository(this.dio);

  Future<String> initUpload({
    required int videoId,
    required String filename,
  }) async {
    final res = await dio.post(
      '${AppConfig.uploadBaseUrl}/uploads/init',
      queryParameters: {
        'video_id': videoId,
        'filename': filename,
      },
    );

    final data = Map<String, dynamic>.from(res.data as Map);
    final uploadId = data['upload_id']?.toString();

    if (uploadId == null || uploadId.isEmpty) {
      throw Exception('upload_id not found in initUpload response');
    }

    return uploadId;
  }

  Future<void> uploadFile({
    required String uploadId,
    required String filePath,
    required String filename,
  }) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        filePath,
        filename: filename,
      ),
    });

    await dio.post(
      '${AppConfig.uploadBaseUrl}/uploads/$uploadId/file',
      data: form,
    );
  }

  Future<void> completeUpload({
    required String uploadId,
    required int size,
    String? checksum,
    String? contentType,
  }) async {
    await dio.post(
      '${AppConfig.uploadBaseUrl}/uploads/$uploadId/complete',
      queryParameters: {
        'size': size,
        if (checksum != null && checksum.isNotEmpty) 'checksum': checksum,
        if (contentType != null && contentType.isNotEmpty)
          'content_type': contentType,
      },
    );
  }
}