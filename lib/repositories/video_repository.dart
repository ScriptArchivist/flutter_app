import 'package:dio/dio.dart';

import '../config/app_config.dart';

class VideoRepository {
  final Dio dio;

  VideoRepository(this.dio);

  Future<List<Map<String, dynamic>>> getVideos({
    int page = 1,
    int perPage = 20,
    bool consistent = false,
  }) async {
    final res = await dio.get(
      '${AppConfig.videoBaseUrl}/videos',
      queryParameters: {
        'page': page,
        'per_page': perPage,
        if (consistent) 'consistent': 1,
      },
    );

    final data = Map<String, dynamic>.from(res.data as Map);
    final items = data['items'] as List<dynamic>? ?? const [];

    return items
        .whereType<Map>()
        .map((e) => _normalizeVideoMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Map<String, dynamic>> getVideo(
    int id, {
    bool consistent = false,
  }) async {
    final res = await dio.get(
      '${AppConfig.videoBaseUrl}/videos/$id',
      queryParameters: {
        if (consistent) 'consistent': 1,
      },
    );

    return _normalizeVideoMap(Map<String, dynamic>.from(res.data as Map));
  }

  Future<Map<String, dynamic>> getPlayback(
    int id, {
    bool consistent = false,
  }) async {
    final res = await dio.get(
      '${AppConfig.videoBaseUrl}/videos/$id/playback',
      queryParameters: {
        if (consistent) 'consistent': 1,
      },
    );

    return _normalizePlaybackMap(Map<String, dynamic>.from(res.data as Map));
  }

  Future<Map<String, dynamic>> createVideo({
    required String title,
    String? description,
    String visibility = 'private',
  }) async {
    final data = <String, dynamic>{
      'title': title.trim(),
      'visibility': visibility,
    };

    if (description != null && description.trim().isNotEmpty) {
      data['description'] = description.trim();
    }

    final res = await dio.post(
      '${AppConfig.videoBaseUrl}/videos',
      data: data,
    );

    return _normalizeVideoMap(Map<String, dynamic>.from(res.data as Map));
  }

  Future<Map<String, dynamic>> updateVideo(
    int id, {
    String? title,
    String? description,
    String? visibility,
  }) async {
    final data = <String, dynamic>{};

    if (title != null) {
      data['title'] = title.trim();
    }

    if (description != null) {
      data['description'] = description.trim();
    }

    if (visibility != null) {
      data['visibility'] = visibility;
    }

    if (data.isEmpty) {
      throw Exception('No fields to update');
    }

    final res = await dio.patch(
      '${AppConfig.videoBaseUrl}/videos/$id',
      data: data,
    );

    return _normalizeVideoMap(Map<String, dynamic>.from(res.data as Map));
  }

  Future<void> deleteVideo(int id) async {
    await dio.delete(
      '${AppConfig.videoBaseUrl}/videos/$id',
    );
  }

  Map<String, dynamic> _normalizeVideoMap(Map<String, dynamic> map) {
    final normalized = Map<String, dynamic>.from(map);

    normalized['hls_url'] = _rewriteHlsUrl(
      normalized['hls_url']?.toString(),
    );

    return normalized;
  }

  Map<String, dynamic> _normalizePlaybackMap(Map<String, dynamic> map) {
    final normalized = Map<String, dynamic>.from(map);

    normalized['hls_url'] = _rewriteHlsUrl(
      normalized['hls_url']?.toString(),
    );

    return normalized;
  }

  String? _rewriteHlsUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) return rawUrl;

    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return rawUrl;

    final host = uri.host.toLowerCase();
    if (host != 'localhost' && host != '127.0.0.1') {
      return rawUrl;
    }

    final originBase = Uri.tryParse(AppConfig.originBaseUrl);
    if (originBase == null || originBase.host.isEmpty) {
      return rawUrl;
    }

    return Uri(
      scheme: originBase.scheme.isEmpty ? 'http' : originBase.scheme,
      host: originBase.host,
      port: originBase.hasPort ? originBase.port : null,
      path: uri.path,
      query: uri.hasQuery ? uri.query : null,
    ).toString();
  }
}