import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../auth/token_storage.dart';
import 'api_config.dart';

typedef OnUnauthorized = Future<void> Function();

class ApiClient {
  final Dio dio;
  final TokenStorage _tokenStorage;
  final OnUnauthorized? onUnauthorized;

  bool _isRefreshing = false;
  final List<Completer<void>> _pendingRequests = [];

  ApiClient({
    required TokenStorage tokenStorage,
    this.onUnauthorized,
    Dio? dioInstance,
  })  : _tokenStorage = tokenStorage,
        dio = dioInstance ??
            Dio(BaseOptions(
              baseUrl: ApiConfig.baseUrl,
              connectTimeout: ApiConfig.connectTimeout,
              receiveTimeout: ApiConfig.receiveTimeout,
              sendTimeout: ApiConfig.sendTimeout,
              responseType: ResponseType.json,
              contentType: 'application/json',
            )) {
    if (kDebugMode) {
      dio.interceptors.add(LogInterceptor(
        request: true,
        requestHeader: false,
        requestBody: false,
        responseHeader: false,
        responseBody: false,
        error: true,
        logPrint: (obj) => debugPrint('[API] $obj'),
      ));
    }
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (options.extra['skipAuth'] != true) {
            final token = await _tokenStorage.accessToken;
            if (token != null) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          handler.next(options);
        },
        onError: (err, handler) async {
          final isUnauthorized = err.response?.statusCode == 401;
          final shouldRetry =
              isUnauthorized && err.requestOptions.extra['retried'] != true;

          if (!shouldRetry) {
            handler.next(err);
            return;
          }

          // Refresh in progress: queue this request
          if (_isRefreshing) {
            final completer = Completer<void>();
            _pendingRequests.add(completer);
            try {
              await completer.future;
              final newToken = await _tokenStorage.accessToken;
              if (newToken == null) {
                handler.next(err);
                return;
              }
              err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
              err.requestOptions.extra['retried'] = true;
              final response = await dio.fetch(err.requestOptions);
              handler.resolve(response);
            } catch (_) {
              handler.next(err);
            }
            return;
          }

          // Start refresh
          _isRefreshing = true;
          try {
            final refreshed = await _refreshToken();
            _isRefreshing = false;
            for (final c in _pendingRequests) {
              c.complete();
            }
            _pendingRequests.clear();

            if (!refreshed) {
              await _tokenStorage.clear();
              await onUnauthorized?.call();
              handler.next(err);
              return;
            }

            final newToken = await _tokenStorage.accessToken;
            err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
            err.requestOptions.extra['retried'] = true;
            final response = await dio.fetch(err.requestOptions);
            handler.resolve(response);
          } catch (e) {
            _isRefreshing = false;
            for (final c in _pendingRequests) {
              c.completeError(e);
            }
            _pendingRequests.clear();
            await _tokenStorage.clear();
            await onUnauthorized?.call();
            handler.next(err);
          }
        },
      ),
    );
  }

  Future<bool> _refreshToken() async {
    final refresh = await _tokenStorage.refreshToken;
    if (refresh == null) return false;
    try {
      final response = await Dio(BaseOptions(baseUrl: ApiConfig.baseUrl)).post(
        '/auth/refresh',
        data: {'refresh_token': refresh},
      );
      final data = response.data as Map<String, dynamic>;
      await _tokenStorage.updateAccessToken(data['access_token'] as String);
      await _tokenStorage.updateRefreshToken(data['refresh_token'] as String);
      return true;
    } catch (_) {
      return false;
    }
  }
}
