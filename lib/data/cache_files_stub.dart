import 'package:shared_preferences/shared_preferences.dart';

/// Web fallback. Browser quotas apply; native clients use private files.
class CacheFiles {
  final SharedPreferences _prefs;
  CacheFiles._(this._prefs);
  static Future<CacheFiles> create() async =>
      CacheFiles._(await SharedPreferences.getInstance());
  Future<String?> read(String uid) async =>
      _prefs.getString('trmatrix.cache.v1.$uid');
  Future<void> write(String uid, String? value) async {
    if (value == null) {
      await _prefs.remove('trmatrix.cache.v1.$uid');
      return;
    }
    if (!await _prefs.setString('trmatrix.cache.v1.$uid', value))
      throw StateError('Device storage is full');
  }
}
