import 'dart:io';

import 'package:dio/dio.dart';

class ApiException implements Exception {
  final String message;

  const ApiException(this.message);

  @override
  String toString() => message;
}

enum NetworkErrorContext {
  generic,
  login,
}

class NetworkErrorMapper {
  static const String invalidResponseMessage =
      'Сервер вернул данные в неожиданном формате.';
  static const String defaultMessage =
      'Не удалось выполнить запрос. Попробуйте снова.';

  static bool isUnauthorized(Object error) {
    if (error is DioException) {
      return error.response?.statusCode == 401;
    }

    return false;
  }

  static String map(
    Object error, {
    String fallbackMessage = defaultMessage,
    NetworkErrorContext context = NetworkErrorContext.generic,
  }) {
    if (error is ApiException) {
      return error.message.isNotEmpty ? error.message : fallbackMessage;
    }

    if (error is DioException) {
      return _mapDioException(
        error,
        fallbackMessage: fallbackMessage,
        context: context,
      );
    }

    if (error is FormatException || error is TypeError) {
      return invalidResponseMessage;
    }

    if (error is SocketException) {
      return _mapSocketException(error);
    }

    final text = error.toString().trim();
    if (text.isEmpty) {
      return fallbackMessage;
    }

    final lower = text.toLowerCase();

    if (_looksLikeInvalidResponse(lower)) {
      return invalidResponseMessage;
    }

    if (_looksLikeNoInternet(lower)) {
      return 'Нет подключения к интернету.';
    }

    if (_looksLikeConnectionRefused(lower)) {
      return 'Не удалось подключиться к серверу.';
    }

    return fallbackMessage;
  }

  static String _mapDioException(
    DioException error, {
    required String fallbackMessage,
    required NetworkErrorContext context,
  }) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Сервер долго не отвечает. Попробуйте снова.';

      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        return _mapStatusCode(
          statusCode,
          error.response?.data,
          fallbackMessage: fallbackMessage,
          context: context,
        );

      case DioExceptionType.connectionError:
        return _mapConnectionLikeError(error, fallbackMessage: fallbackMessage);

      case DioExceptionType.cancel:
        return 'Запрос был отменён.';

      case DioExceptionType.badCertificate:
        return 'Не удалось установить безопасное соединение с сервером.';

      case DioExceptionType.unknown:
        return _mapConnectionLikeError(error, fallbackMessage: fallbackMessage);
    }
  }

  static String _mapConnectionLikeError(
    DioException error, {
    required String fallbackMessage,
  }) {
    final raw = [
      error.message,
      error.error?.toString(),
      error.response?.data?.toString(),
    ].whereType<String>().join(' ').toLowerCase();

    if (_looksLikeNoInternet(raw)) {
      return 'Нет подключения к интернету.';
    }

    if (_looksLikeConnectionRefused(raw)) {
      return 'Не удалось подключиться к серверу.';
    }

    if (_looksLikeInvalidResponse(raw)) {
      return invalidResponseMessage;
    }

    return fallbackMessage;
  }

  static String _mapSocketException(SocketException error) {
    final raw = error.toString().toLowerCase();

    if (_looksLikeNoInternet(raw)) {
      return 'Нет подключения к интернету.';
    }

    if (_looksLikeConnectionRefused(raw)) {
      return 'Не удалось подключиться к серверу.';
    }

    return defaultMessage;
  }

  static String _mapStatusCode(
    int? statusCode,
    dynamic data, {
    required String fallbackMessage,
    required NetworkErrorContext context,
  }) {
    final serverMessage = _extractServerMessage(data);

    switch (statusCode) {
      case 400:
        return serverMessage ?? 'Некорректный запрос.';
      case 401:
        if (context == NetworkErrorContext.login) {
          return serverMessage ?? 'Неверный username или password.';
        }
        return 'Требуется авторизация. Войдите снова.';
      case 403:
        return 'Доступ запрещён.';
      case 404:
        return 'Запрашиваемый ресурс не найден.';
      case 409:
        return serverMessage ?? 'Конфликт данных. Попробуйте обновить экран.';
      case 422:
        return serverMessage ?? 'Проверьте правильность введённых данных.';
      case 500:
        return 'Внутренняя ошибка сервера. Попробуйте позже.';
      default:
        return serverMessage ?? fallbackMessage;
    }
  }

  static String? _extractServerMessage(dynamic data) {
    if (data == null) {
      return null;
    }

    if (data is Map) {
      final map = Map<String, dynamic>.from(data);

      final errorValue = map['error'];
      if (errorValue is Map) {
        final err = Map<String, dynamic>.from(errorValue);

        final message = err['message']?.toString().trim();
        if (message != null && message.isNotEmpty) {
          return message;
        }

        final code = err['code']?.toString().trim();
        if (code != null && code.isNotEmpty) {
          return code;
        }
      }

      final detail = map['detail'];
      if (detail is String && detail.trim().isNotEmpty) {
        return detail.trim();
      }

      if (detail is List) {
        final parts = detail
            .map((item) {
              if (item is Map) {
                final itemMap = Map<String, dynamic>.from(item);
                final msg = itemMap['msg']?.toString().trim();
                if (msg != null && msg.isNotEmpty) {
                  return msg;
                }
              }

              final text = item.toString().trim();
              return text.isNotEmpty ? text : null;
            })
            .whereType<String>()
            .toList();

        if (parts.isNotEmpty) {
          return parts.join('\n');
        }
      }

      final message = map['message']?.toString().trim();
      if (message != null && message.isNotEmpty) {
        return message;
      }
    }

    if (data is String) {
      final text = data.trim();
      if (text.isNotEmpty && !text.startsWith('<!DOCTYPE html')) {
        return text;
      }
    }

    return null;
  }

  static bool _looksLikeNoInternet(String text) {
    return text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('unable to resolve host') ||
        text.contains('no address associated with hostname') ||
        text.contains('temporary failure in name resolution') ||
        text.contains('socketexception') && text.contains('unreachable');
  }

  static bool _looksLikeConnectionRefused(String text) {
    return text.contains('connection refused') ||
        text.contains('actively refused') ||
        text.contains('errno = 111') ||
        text.contains('os error: connection refused');
  }

  static bool _looksLikeInvalidResponse(String text) {
    return text.contains('type ') && text.contains('is not a subtype of') ||
        text.contains('formatexception') ||
        text.contains('unexpected response format') ||
        text.contains('invalid response format') ||
        text.contains('json object');
  }
}