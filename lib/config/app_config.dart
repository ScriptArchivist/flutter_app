import 'package:flutter/foundation.dart';

class AppConfig {
  static const _identityBaseUrlRaw = String.fromEnvironment(
    'IDENTITY_BASE_URL',
    defaultValue: 'http://192.168.1.12:8001',
  );

  static const _videoBaseUrlRaw = String.fromEnvironment(
    'VIDEO_BASE_URL',
    defaultValue: 'http://192.168.1.12:8003/api/v1',
  );

  static const _uploadBaseUrlRaw = String.fromEnvironment(
    'UPLOAD_BASE_URL',
    defaultValue: 'http://192.168.1.12:8002/api/v1',
  );

  static const _liveBaseUrlRaw = String.fromEnvironment(
    'LIVE_BASE_URL',
    defaultValue: 'http://192.168.1.12:8004',
  );

  static const _originBaseUrlRaw = String.fromEnvironment(
    'ORIGIN_BASE_URL',
    defaultValue: 'http://192.168.1.12:8080',
  );

  static const bool _enableNetworkLogsFromDefine = bool.fromEnvironment(
    'ENABLE_NETWORK_LOGS',
    defaultValue: false,
  );

  static String get identityBaseUrl => _normalize(_identityBaseUrlRaw);
  static String get videoBaseUrl => _normalize(_videoBaseUrlRaw);
  static String get uploadBaseUrl => _normalize(_uploadBaseUrlRaw);
  static String get liveBaseUrl => _normalize(_liveBaseUrlRaw);
  static String get originBaseUrl => _normalize(_originBaseUrlRaw);

  static String get identityLoginUrl => '$identityBaseUrl/auth/login';

  static bool get hasIdentityBaseUrl => identityBaseUrl.isNotEmpty;

  static bool get enableNetworkLogs {
    if (kDebugMode) {
      return true;
    }

    return _enableNetworkLogsFromDefine;
  }

  static String _normalize(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }

    return trimmed;
  }
}