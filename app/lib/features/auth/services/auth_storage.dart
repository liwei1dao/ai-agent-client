import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';

/// Persists the logged-in [User] (including token) to shared_preferences.
class AuthStorage {
  static const _key = 'auth.current_user.v1';

  Future<User?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return User.decode(raw);
    } catch (_) {
      await prefs.remove(_key);
      return null;
    }
  }

  Future<void> write(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, user.encode());
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
