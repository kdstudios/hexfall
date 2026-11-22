import 'package:shared_preferences/shared_preferences.dart';

/// Tiny async key/value abstraction so persistence is testable without
/// plugins. Production uses shared_preferences (SharedPreferences on Android /
/// iOS, localStorage on the web).
abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class MemoryStore implements KeyValueStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);
}

class PrefsStore implements KeyValueStore {
  PrefsStore._(this._prefs);
  final SharedPreferences _prefs;

  static Future<PrefsStore> open() async => PrefsStore._(await SharedPreferences.getInstance());

  @override
  Future<String?> read(String key) async => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) async {
    await _prefs.setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await _prefs.remove(key);
  }
}
