import 'package:dio/dio.dart';
import '../errors/app_error.dart';
import '../models/dashboard_stats.dart';
import 'api_client.dart';

class StatsApi {
  final ApiClient _client;
  StatsApi(this._client);

  Future<DashboardStats> dashboard() async {
    try {
      final res = await _client.dio.get('/stats/dashboard');
      return DashboardStats.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }
}
