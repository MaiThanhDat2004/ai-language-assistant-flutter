import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../errors/app_error.dart';
import '../models/user.dart';
import 'api_client.dart';

class AuthApi {
  final ApiClient _client;

  AuthApi(this._client);

  Future<AuthTokens> register({
    required String username,
    required String email,
    required String password,
    String? fullName,
  }) async {
    try {
      final res = await _client.dio.post(
        '/auth/register',
        data: {
          'username': username,
          'email': email,
          'password': password,
          if (fullName != null && fullName.isNotEmpty) 'full_name': fullName,
        },
        options: Options(extra: {'skipAuth': true}),
      );
      return AuthTokens.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  Future<AuthTokens> login({
    required String username,
    required String password,
    String? deviceInfo,
  }) async {
    try {
      final res = await _client.dio.post(
        '/auth/login',
        data: {
          'username': username,
          'password': password,
          'device_info': ?deviceInfo,
        },
        options: Options(extra: {'skipAuth': true}),
      );
      return AuthTokens.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  Future<void> logout(String refreshToken) async {
    try {
      await _client.dio.post(
        '/auth/logout',
        data: {'refresh_token': refreshToken},
        options: Options(extra: {'skipAuth': true}),
      );
    } on DioException catch (_) {
      // Ignore — we'll clear local tokens regardless
    }
  }

  Future<User> getMe() async {
    try {
      final res = await _client.dio.get('/auth/me');
      return User.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  Future<User> updateProfile({
    String? fullName,
    String? avatarUrl,
    String? preferredLanguage,
  }) async {
    try {
      final res = await _client.dio.put('/auth/me', data: {
        'full_name': ?fullName,
        'avatar_url': ?avatarUrl,
        'preferred_language': ?preferredLanguage,
      });
      return User.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  /// Upload avatar từ file path (mobile/desktop).
  Future<User> uploadAvatar({required String filePath}) async {
    try {
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
      });
      return _postAvatar(form);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  /// Bytes version — bắt buộc cho web (image_picker trả blob URL, không phải path).
  Future<User> uploadAvatarFromBytes({
    required Uint8List bytes,
    required String filename,
  }) async {
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      });
      return _postAvatar(form);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  Future<User> _postAvatar(FormData form) async {
    final res = await _client.dio.post(
      '/auth/avatar',
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );
    return User.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      await _client.dio.post('/auth/change-password', data: {
        'old_password': oldPassword,
        'new_password': newPassword,
      });
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  /// Đặt lại mật khẩu self-service: phải khớp CẢ username lẫn email của cùng
  /// 1 tài khoản (không cần email server). Trả message thành công từ backend.
  Future<void> resetPassword({
    required String username,
    required String email,
    required String newPassword,
  }) async {
    try {
      await _client.dio.post(
        '/auth/reset-password',
        data: {
          'username': username,
          'email': email,
          'new_password': newPassword,
        },
        options: Options(extra: {'skipAuth': true}),
      );
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }
}
