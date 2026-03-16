import 'package:flutter/foundation.dart';

import '../core/network/token_storage.dart';

enum AuthStatus {
  unknown,
  authenticated,
  unauthenticated,
}

class AuthStateController extends ChangeNotifier {
  final TokenStorage tokenStorage;

  AuthStateController(this.tokenStorage);

  AuthStatus _status = AuthStatus.unknown;
  bool _isUnauthorizedHandlingInProgress = false;

  AuthStatus get status => _status;

  bool get isAuthenticated => _status == AuthStatus.authenticated;

  Future<void> init() async {
    final token = await tokenStorage.getToken();
    final hasToken = token != null && token.trim().isNotEmpty;

    _setStatus(
      hasToken ? AuthStatus.authenticated : AuthStatus.unauthenticated,
    );
  }

  Future<void> setAuthenticated(String token) async {
    final normalizedToken = token.trim();

    if (normalizedToken.isEmpty) {
      await logout();
      return;
    }

    await tokenStorage.saveToken(normalizedToken);
    _setStatus(AuthStatus.authenticated);
  }

  Future<void> logout() async {
    await tokenStorage.clear();
    _setStatus(AuthStatus.unauthenticated);
  }

  Future<void> handleUnauthorized() async {
    if (_isUnauthorizedHandlingInProgress) {
      return;
    }

    _isUnauthorizedHandlingInProgress = true;

    try {
      await logout();
    } finally {
      _isUnauthorizedHandlingInProgress = false;
    }
  }

  void _setStatus(AuthStatus value) {
    if (_status == value) {
      return;
    }

    _status = value;
    notifyListeners();
  }
}