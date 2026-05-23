import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

class ApiConfig {
  ApiConfig._();

  // Backend URL theo platform:
  // - Web/Windows/macOS/iOS sim: http://localhost:8000
  // - Android emulator:          http://10.0.2.2:8000
  // - Thiết bị thật:             http://<IP-máy-bạn>:8000
  static String get baseUrl {
    if (kIsWeb) return 'http://localhost:8000';
    try {
      if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    } catch (_) {}
    return 'http://localhost:8000';
  }

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 240);
  static const Duration sendTimeout = Duration(seconds: 60);
}
