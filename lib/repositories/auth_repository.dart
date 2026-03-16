import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/network/token_storage.dart';

class AuthRepository {
  final Dio dio;
  final TokenStorage storage;

  AuthRepository(this.dio, this.storage);

  Future<void> login(String username, String password) async {
    if (!AppConfig.hasIdentityBaseUrl) {
      throw Exception(
        'IDENTITY_BASE_URL is empty. APK was likely built without correct --dart-define.',
      );
    }

    final loginUrl = AppConfig.identityLoginUrl;

    NetworkLogBuffer.add('AUTH LOGIN URL => $loginUrl');
    debugPrint('AUTH LOGIN URL => $loginUrl');

    final res = await dio.post(
      loginUrl,
      data: {
        'username': username,
        'password': password,
      },
      options: Options(
        extra: {
          'skipAuth': true,
        },
      ),
    );

    NetworkLogBuffer.add('AUTH LOGIN STATUS => ${res.statusCode}');

    if (res.statusCode != 200 && res.statusCode != 201) {
      throw DioException(
        requestOptions: res.requestOptions,
        response: res,
        error: 'Unexpected login status: ${res.statusCode}',
        type: DioExceptionType.badResponse,
      );
    }

    final raw = res.data;
    if (raw is! Map) {
      throw Exception('Login response is not a JSON object');
    }

    final data = Map<String, dynamic>.from(raw);
    final token = (data['access_token'] ?? data['token'])?.toString();

    if (token == null || token.isEmpty) {
      throw Exception('Token not found in login response');
    }

    await storage.saveToken(token);
    NetworkLogBuffer.add('AUTH TOKEN SAVED');
  }

  Future<void> logout() async {
    await storage.clear();
    NetworkLogBuffer.add('AUTH LOGOUT');
  }
}