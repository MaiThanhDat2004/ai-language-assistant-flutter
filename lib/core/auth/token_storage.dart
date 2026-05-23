import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';
  static const _kUserId = 'user_id';
  static const _kUsername = 'username';
  static const _kThemeMode = 'theme_mode'; // 'light' | 'dark' | 'system'

  final FlutterSecureStorage _storage;
  final Map<String, String> _memoryFallback = {};

  TokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              webOptions: WebOptions(
                dbName: 'lang_assistant',
                publicKey: 'lang_assistant_pub_key',
              ),
            );

  Future<void> _write(String key, String value) async {
    _memoryFallback[key] = value;
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      // ignore: avoid_print
      print('TokenStorage.write($key) fallback to memory: $e');
    }
  }

  Future<String?> _read(String key) async {
    try {
      final v = await _storage.read(key: key);
      if (v != null) return v;
    } catch (e) {
      // ignore: avoid_print
      print('TokenStorage.read($key) fallback to memory: $e');
    }
    return _memoryFallback[key];
  }

  Future<void> _delete(String key) async {
    _memoryFallback.remove(key);
    try {
      await _storage.delete(key: key);
    } catch (_) {}
  }

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required String userId,
    required String username,
  }) async {
    await _write(_kAccess, accessToken);
    await _write(_kRefresh, refreshToken);
    await _write(_kUserId, userId);
    await _write(_kUsername, username);
  }

  Future<String?> get accessToken => _read(_kAccess);
  Future<String?> get refreshToken => _read(_kRefresh);
  Future<String?> get userId => _read(_kUserId);
  Future<String?> get username => _read(_kUsername);

  Future<void> updateAccessToken(String token) => _write(_kAccess, token);
  Future<void> updateRefreshToken(String token) => _write(_kRefresh, token);

  Future<bool> get hasTokens async {
    final access = await accessToken;
    final refresh = await refreshToken;
    return access != null && refresh != null;
  }

  Future<void> clear() async {
    await _delete(_kAccess);
    await _delete(_kRefresh);
    await _delete(_kUserId);
    await _delete(_kUsername);
    // KHÔNG xoá theme_mode khi logout — user vẫn giữ preference của họ
  }

  Future<String?> get themeMode => _read(_kThemeMode);
  Future<void> setThemeMode(String mode) => _write(_kThemeMode, mode);
}
