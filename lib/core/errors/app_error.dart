import 'package:dio/dio.dart';

class AppError implements Exception {
  final String code;
  final String message;
  final int? statusCode;

  const AppError({
    required this.code,
    required this.message,
    this.statusCode,
  });

  factory AppError.fromDio(DioException e) {
    final response = e.response;
    if (response != null) {
      final data = response.data;
      if (data is Map<String, dynamic> && data['error'] is Map) {
        final err = data['error'] as Map<String, dynamic>;
        return AppError(
          code: err['code']?.toString() ?? 'UNKNOWN',
          message: err['message']?.toString() ?? 'Đã có lỗi xảy ra',
          statusCode: response.statusCode,
        );
      }
      // FastAPI mặc định trả {"detail": "..."} khi raise HTTPException trực
      // tiếp (router auth/login không bọc envelope). Ưu tiên hiện message này
      // thay vì câu chung chung — vd sai mật khẩu phải thấy đúng lý do, không
      // phải "Phiên đăng nhập đã hết hạn".
      if (data is Map<String, dynamic> && data['detail'] is String) {
        final detail = (data['detail'] as String).trim();
        if (detail.isNotEmpty) {
          return AppError(
            code: 'HTTP_${response.statusCode}',
            message: detail,
            statusCode: response.statusCode,
          );
        }
      }
      return AppError(
        code: 'HTTP_${response.statusCode}',
        message: _statusMessage(response.statusCode),
        statusCode: response.statusCode,
      );
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return const AppError(
        code: 'TIMEOUT',
        message: 'Kết nối quá thời gian, hãy thử lại',
      );
    }
    if (e.type == DioExceptionType.connectionError) {
      return const AppError(
        code: 'NO_CONNECTION',
        message: 'Không thể kết nối tới máy chủ',
      );
    }
    return AppError(
      code: 'UNKNOWN',
      message: e.message ?? 'Đã có lỗi không xác định',
    );
  }

  static String _statusMessage(int? code) {
    switch (code) {
      case 400:
        return 'Yêu cầu không hợp lệ';
      case 401:
        return 'Phiên đăng nhập đã hết hạn';
      case 403:
        return 'Bạn không có quyền thực hiện hành động này';
      case 404:
        return 'Không tìm thấy dữ liệu';
      case 502:
        return 'Máy chủ AI tạm thời không phản hồi, thử lại';
      case 500:
        return 'Lỗi máy chủ, vui lòng thử lại';
      default:
        return 'Đã có lỗi xảy ra';
    }
  }

  @override
  String toString() => 'AppError($code): $message';
}
