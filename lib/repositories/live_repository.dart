import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../core/network/error_parser.dart';
import '../models/video_models.dart';

class HlsAvailabilityResult {
  final bool available;
  final int? statusCode;
  final String bodyPreview;

  const HlsAvailabilityResult({
    required this.available,
    required this.statusCode,
    required this.bodyPreview,
  });
}

class LiveRepository {
  final Dio dio;

  LiveRepository(this.dio);

  Future<Map<String, dynamic>> createSession({
    String? streamKey,
    int ttlSeconds = 1800,
  }) async {
    final data = <String, dynamic>{
      'ttl_seconds': ttlSeconds,
    };

    if (streamKey != null && streamKey.trim().isNotEmpty) {
      data['stream_key'] = streamKey.trim();
    }

    final res = await dio.post(
      '${AppConfig.liveBaseUrl}/live/sessions',
      data: data,
    );

    return _normalizeSessionResponse(res.data);
  }

  Future<Map<String, dynamic>> getSession(String streamKey) async {
    final res = await dio.get(
      '${AppConfig.liveBaseUrl}/live/sessions/$streamKey',
    );

    return _normalizeSessionResponse(res.data);
  }

  Future<List<ActiveLiveListItem>> getActiveStreams() async {
    final res = await dio.get(
      '${AppConfig.liveBaseUrl}/live/sessions/active',
    );

    final items = _extractActiveStreamItems(res.data);

    return items
        .map((item) => _normalizeActiveStreamItem(item))
        .where((item) => item.streamKey.isNotEmpty)
        .toList();
  }

  Future<void> stopSession(int sessionId) async {
    await dio.delete(
      '${AppConfig.liveBaseUrl}/live/sessions/$sessionId',
    );
  }

  Future<HlsAvailabilityResult> checkHlsAvailability(String url) async {
    try {
      final res = await dio.get(
        url,
        options: Options(
          responseType: ResponseType.plain,
          extra: const {
            'skipAuth': true,
          },
          headers: const {
            'Accept':
                'application/vnd.apple.mpegurl, application/x-mpegURL, text/plain',
          },
          validateStatus: (status) =>
              status != null && status >= 200 && status < 500,
        ),
      );

      final body = res.data?.toString() ?? '';
      final available = res.statusCode == 200 && body.contains('#EXTM3U');

      return HlsAvailabilityResult(
        available: available,
        statusCode: res.statusCode,
        bodyPreview: _truncate(body),
      );
    } catch (e) {
      return HlsAvailabilityResult(
        available: false,
        statusCode: null,
        bodyPreview: e.toString(),
      );
    }
  }

  Map<String, dynamic> _normalizeSessionResponse(dynamic raw) {
    final map = _requireMap(raw);

    if (map['session'] is Map) {
      return {
        'session': _requireMap(map['session']),
        'rtmp_url': _rewriteRtmpUrl(map['rtmp_url']?.toString()),
        'hls_url': _rewriteHlsUrl(map['hls_url']?.toString()),
      };
    }

    return {
      'session': map,
      'rtmp_url': _rewriteRtmpUrl(map['rtmp_url']?.toString()),
      'hls_url': _rewriteHlsUrl(map['hls_url']?.toString()),
    };
  }

  List<Map<String, dynamic>> _extractActiveStreamItems(dynamic raw) {
    if (raw is List) {
      return raw.whereType<Map>().map(_requireMap).toList();
    }

    if (raw is Map) {
      final map = _requireMap(raw);

      const keys = [
        'items',
        'streams',
        'sessions',
        'results',
        'data',
      ];

      for (final key in keys) {
        final value = map[key];
        if (value is List) {
          return value.whereType<Map>().map(_requireMap).toList();
        }
      }
    }

    throw const ApiException(NetworkErrorMapper.invalidResponseMessage);
  }

  ActiveLiveListItem _normalizeActiveStreamItem(Map<String, dynamic> raw) {
    final normalized = Map<String, dynamic>.from(raw);

    normalized['hls_url'] = _rewriteHlsUrl(raw['hls_url']?.toString());

    return ActiveLiveListItem.fromJson(normalized);
  }

  Map<String, dynamic> _requireMap(dynamic raw) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }

    throw const ApiException(NetworkErrorMapper.invalidResponseMessage);
  }

  String? _rewriteRtmpUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) return rawUrl;

    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return rawUrl;

    final liveBase = Uri.tryParse(AppConfig.liveBaseUrl);
    if (liveBase == null || liveBase.host.isEmpty) {
      return rawUrl;
    }

    final hasHost = uri.host.isNotEmpty;
    final host = uri.host.toLowerCase();

    if (!hasHost) {
      return Uri(
        scheme: 'rtmp',
        host: liveBase.host,
        port: 1935,
        path: uri.path.startsWith('/') ? uri.path : '/${uri.path}',
        query: uri.hasQuery ? uri.query : null,
      ).toString();
    }

    if (host != 'localhost' && host != '127.0.0.1') {
      return rawUrl;
    }

    return Uri(
      scheme: 'rtmp',
      host: liveBase.host,
      port: uri.hasPort ? uri.port : 1935,
      path: uri.path,
      query: uri.hasQuery ? uri.query : null,
    ).toString();
  }

  String? _rewriteHlsUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) return rawUrl;

    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return rawUrl;

    final originBase = Uri.tryParse(AppConfig.originBaseUrl);
    if (originBase == null || originBase.host.isEmpty) {
      return rawUrl;
    }

    final hasHost = uri.host.isNotEmpty;
    final host = uri.host.toLowerCase();

    if (!hasHost) {
      return Uri(
        scheme: originBase.scheme.isEmpty ? 'http' : originBase.scheme,
        host: originBase.host,
        port: originBase.hasPort ? originBase.port : null,
        path: uri.path.startsWith('/') ? uri.path : '/${uri.path}',
        query: uri.hasQuery ? uri.query : null,
      ).toString();
    }

    if (host != 'localhost' && host != '127.0.0.1') {
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

  String _truncate(String value, {int max = 300}) {
    if (value.length <= max) {
      return value;
    }

    return '${value.substring(0, max)}... <truncated>';
  }
}