import 'package:shared_preferences/shared_preferences.dart';

class TokenStorage {
  static const _key = 'auth_token';

  Future<SharedPreferences> get _prefs async =>
      await SharedPreferences.getInstance();

  Future<void> saveToken(String token) async {
    final prefs = await _prefs;
    await prefs.setString(_key, token);
  }

  Future<String?> getToken() async {
    final prefs = await _prefs;
    return prefs.getString(_key);
  }

  Future<void> clear() async {
    final prefs = await _prefs;
    await prefs.remove(_key);
  }
}