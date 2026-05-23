import 'package:dio/dio.dart';
import '../errors/app_error.dart';
import '../models/template.dart';
import 'api_client.dart';

class TemplatesApi {
  final ApiClient _client;

  TemplatesApi(this._client);

  Future<List<Template>> list({
    String? category,
    bool? isFavorite,
    bool? isUserCreated,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final res = await _client.dio.get('/templates/', queryParameters: {
        'category': ?category,
        'is_favorite': ?isFavorite,
        'is_user_created': ?isUserCreated,
        'limit': limit,
        'offset': offset,
      });
      final data = res.data;
      final List items =
          data is List ? data : (data['items'] as List? ?? []);
      return items
          .map((e) => Template.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  Future<Template> get(String id) async {
    try {
      final res = await _client.dio.get('/templates/$id');
      return Template.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  Future<Template> create({
    required String name,
    required String systemPrompt,
    String? description,
    String responseLanguage = 'vi',
    String? category,
  }) async {
    try {
      final res = await _client.dio.post('/templates/', data: {
        'name': name,
        'system_prompt': systemPrompt,
        'description': ?description,
        'default_response_language': responseLanguage,
        'category': ?category,
      });
      return Template.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  Future<void> toggleFavorite(String id, bool isFavorite) async {
    try {
      if (isFavorite) {
        await _client.dio.post('/templates/$id/favorite');
      } else {
        await _client.dio.delete('/templates/$id/favorite');
      }
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }
}
