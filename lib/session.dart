import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'config.dart';

/// Who is signed in, and to which server.
class Session {
  Session(this.baseUrl, this.token, this.username, this.role);
  final String baseUrl;
  final String token;
  final String username;
  final String role;

  /// Set by whoever owns the sign-in state; runs once when the server refuses the token.
  void Function()? onExpired;
  bool _expired = false;

  void expire() {
    if (_expired) return; // a poll, a list and an upload can all fail together
    _expired = true;
    onExpired?.call();
  }

  ApiClient get api => ApiClient(baseUrl, token: token, onUnauthorized: expire);

  /// Owner and manager see every scan and can pick the product.
  bool get isStaffLead => role == 'owner' || role == 'manager';
  bool get isOwner => role == 'owner';

  /// Who may sell (New Bill, Buyers), as on the desktop.
  bool get canSell => isStaffLead || role == 'sales';

  /// The desktop's sidebar rules: which screens this role is shown.
  bool allows(String module) => switch (role) {
        'owner' => true,
        'manager' => module != 'staff',
        'sales' => !const {
            'reports', 'lab', 'materials', 'purchases', 'staff', 'wages', 'expenses', 'profit'
          }.contains(module),
        'achari' || 'worker' || 'artisan' =>
          const {'home', 'stock', 'workforce', 'wages', 'lab'}.contains(module),
        _ => module == 'home',
      };


  /// Temple restorations are for the owner and artisans only.
  bool get canRestore => role == 'owner' || role == 'artisan';
}

/// The token lives in the phone's secure storage; the rest is not secret.
class SessionStore {
  static const _secure = FlutterSecureStorage();

  static Future<Session?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final token = await _secure.read(key: 'token');
    if (token == null) return null;
    return Session(apiBaseUrl, token, prefs.getString('username') ?? '',
        prefs.getString('role') ?? '');
  }

  static Future<Session> save(LoginResult login) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', login.username);
    await prefs.setString('role', login.role);
    await _secure.write(key: 'token', value: login.token);
    return Session(apiBaseUrl, login.token, login.username, login.role);
  }

  static Future<void> clear() async {
    await _secure.delete(key: 'token');
  }
}
