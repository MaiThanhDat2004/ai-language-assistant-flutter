import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

class ApiConfig {
  ApiConfig._();

  static String get baseUrl {
    if (kIsWeb) return 'http://localhost:8000';

    try {
      if (Platform.isAndroid) {
        // Điện thoại thật cùng mạng với laptop (hiện: hotspot 4G — laptop 192.168.100.63)
        return 'http://192.168.100.63:8000';
      }
    } catch (_) {}

    return 'http://localhost:8000';
  }

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 240);
  static const Duration sendTimeout = Duration(seconds: 60);
}