import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../config/app_config.dart';
import 'token_storage.dart';

class NetworkLogBuffer {
  static final List<String> _lines = <String>[];

  static List<String> get lines => List.unmodifiable(_lines);

  static String get text => _lines.join('\n');

  static void add(String message) {
    if (!AppConfig.enableNetworkLogs) {
      return;
    }

    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final line = '[${DateTime.now().toIso8601String()}] $trimmed';
    _lines.add(line);

    if (_lines.length > 200) {
      _lines.removeAt(0);
    }

    debugPrint(line);
  }

  static void clear() {
    _lines.clear();
  }
}

class ApiClient {
  final Dio dio;
  final TokenStorage tokenStorage;
  final Future<void> Function()? onUnauthorized;

  ApiClient(
    this.dio,
    this.tokenStorage, {
    this.onUnauthorized,
  }) {
    dio.options = dio.options.copyWith(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      responseType: ResponseType.json,
    );

    dio.interceptors.add(
      QueuedInterceptorsWrapper(
        onRequest: (options, handler) async {
          final skipAuth = options.extra['skipAuth'] == true;

          if (!skipAuth) {
            final token = await tokenStorage.getToken();

            if (token != null &&
                token.isNotEmpty &&
                options.headers['Authorization'] == null) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }

          if (AppConfig.enableNetworkLogs) {
            NetworkLogBuffer.add('REQUEST ${options.method} ${options.uri}');
            NetworkLogBuffer.add(
              'REQUEST HEADERS ${_sanitizeHeaders(options.headers)}',
            );

            if (options.data != null) {
              NetworkLogBuffer.add(
                'REQUEST BODY ${_sanitizeBody(options.data)}',
              );
            }
          }

          handler.next(options);
        },
        onResponse: (response, handler) {
          if (AppConfig.enableNetworkLogs) {
            NetworkLogBuffer.add(
              'RESPONSE ${response.statusCode} ${response.requestOptions.method} ${response.requestOptions.uri}',
            );

            if (response.data != null) {
              NetworkLogBuffer.add(
                'RESPONSE BODY ${_truncate(_stringify(response.data))}',
              );
            }
          }

          handler.next(response);
        },
        onError: (e, handler) async {
          if (AppConfig.enableNetworkLogs) {
            NetworkLogBuffer.add(
              'ERROR ${e.requestOptions.method} ${e.requestOptions.uri}',
            );
            NetworkLogBuffer.add('ERROR TYPE ${e.type}');
            NetworkLogBuffer.add('ERROR MESSAGE ${e.message}');
            NetworkLogBuffer.add('ERROR STATUS ${e.response?.statusCode}');

            if (e.response?.data != null) {
              NetworkLogBuffer.add(
                'ERROR BODY ${_truncate(_stringify(e.response?.data))}',
              );
            }

            if (e.error != null) {
              NetworkLogBuffer.add(
                'ERROR INNER ${_truncate(e.error.toString())}',
              );
            }
          }

          if (e.response?.statusCode == 401 && onUnauthorized != null) {
            if (AppConfig.enableNetworkLogs) {
              NetworkLogBuffer.add('AUTH UNAUTHORIZED => CLEAR TOKEN');
            }
            await onUnauthorized!.call();
          }

          handler.next(e);
        },
      ),
    );
  }

  static Map<String, dynamic> _sanitizeHeaders(Map<String, dynamic> headers) {
    final result = <String, dynamic>{};

    headers.forEach((key, value) {
      final lowerKey = key.toLowerCase();

      if (lowerKey == 'authorization') {
        result[key] = 'Bearer ***';
      } else {
        result[key] = value;
      }
    });

    return result;
  }

  static dynamic _sanitizeBody(dynamic body) {
    if (body is Map) {
      final map = Map<String, dynamic>.from(body);
      final result = <String, dynamic>{};

      map.forEach((key, value) {
        final lowerKey = key.toLowerCase();

        if (lowerKey.contains('password')) {
          result[key] = '***';
        } else if (lowerKey.contains('token')) {
          result[key] = '***';
        } else {
          result[key] = value;
        }
      });

      return result;
    }

    return body;
  }

  static String _stringify(dynamic value) {
    try {
      return value.toString();
    } catch (_) {
      return '<unprintable>';
    }
  }

  static String _truncate(String value, {int max = 1200}) {
    if (value.length <= max) {
      return value;
    }

    return '${value.substring(0, max)}... <truncated>';
  }
}