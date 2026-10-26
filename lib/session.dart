import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// Who is signed in, and to which server.
class Session {
  Session(this.baseUrl, this.token, this.username, this.role);
  final String baseUrl;
  final String token;
  final String username;
  final String role;

  ApiClient get api => ApiClient(baseUrl, token: token);

  /// Owner and manager see every scan and can pick the product.
  bool get isStaffLead => role == 'owner' || role == 'manager';
}

/// The token lives in the phone's secure storage; the rest is not secret.
class SessionStore {
  static const _secure = FlutterSecureStorage();

  static Future<Session?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final token = await _secure.read(key: 'token');
    final url = prefs.getString('baseUrl');
    if (token == null || url == null) return null;
    return Session(url, token, prefs.getString('username') ?? '',
        prefs.getString('role') ?? '');
  }

  static Future<String?> lastServer() async =>
      (await SharedPreferences.getInstance()).getString('baseUrl');

  static Future<Session> save(String baseUrl, LoginResult login) async {
    final prefs = await SharedPreferences.getInstance();
    final url = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    await prefs.setString('baseUrl', url);
    await prefs.setString('username', login.username);
    await prefs.setString('role', login.role);
    await _secure.write(key: 'token', value: login.token);
    return Session(url, login.token, login.username, login.role);
  }

  static Future<void> clear() async {
    await _secure.delete(key: 'token');
  }
}
