import 'package:dio/dio.dart';
import '../errors/app_error.dart';
import '../models/language.dart';
import 'api_client.dart';

class LanguagesApi {
  final ApiClient _client;

  LanguagesApi(this._client);

  Future<List<Language>> list() async {
    try {
      final res = await _client.dio.get('/languages/');
      final data = res.data;
      final List items = data is List ? data : (data['items'] as List? ?? []);
      return items
          .map((e) => Language.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }
}
