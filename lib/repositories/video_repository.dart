import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../core/network/error_parser.dart';

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

    final data = _requireMap(res.data);
    final rawItems = data['items'];

    if (rawItems is! List) {
      throw const ApiException(NetworkErrorMapper.invalidResponseMessage);
    }

    return rawItems
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

    return _normalizeVideoMap(_requireMap(res.data));
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

    return _normalizePlaybackMap(_requireMap(res.data));
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

    return _normalizeVideoMap(_requireMap(res.data));
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
      throw const ApiException('Нет данных для обновления.');
    }

    final res = await dio.patch(
      '${AppConfig.videoBaseUrl}/videos/$id',
      data: data,
    );

    return _normalizeVideoMap(_requireMap(res.data));
  }

  Future<void> deleteVideo(int id) async {
    await dio.delete(
      '${AppConfig.videoBaseUrl}/videos/$id',
    );
  }

  Map<String, dynamic> _requireMap(dynamic raw) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }

    throw const ApiException(NetworkErrorMapper.invalidResponseMessage);
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