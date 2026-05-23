import 'package:dio/dio.dart';
import '../errors/app_error.dart';
import '../models/session.dart';
import 'api_client.dart';

class SessionsApi {
  final ApiClient _client;

  SessionsApi(this._client);

  Future<ChatSession> create({
    String? templateId,
    String? title,
    required String responseLanguage,
    String? contextPrompt,
  }) async {
    try {
      final res = await _client.dio.post('/sessions/', data: {
        'template_id': ?templateId,
        'title': ?title,
        'response_language': responseLanguage,
        'context_prompt': ?contextPrompt,
      });
      return ChatSession.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  Future<List<ChatSession>> list({
    bool includeArchived = false,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final res = await _client.dio.get('/sessions/', queryParameters: {
        'include_archived': includeArchived,
        'limit': limit,
        'offset': offset,
      });
      final data = res.data;
      final List items =
          data is List ? data : (data['items'] as List? ?? []);
      return items
          .map((e) => ChatSession.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  Future<ChatSession> get(String id) async {
    try {
      final res = await _client.dio.get('/sessions/$id');
      return ChatSession.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  Future<ChatSession> update(
    String id, {
    String? title,
    String? contextPrompt,
    bool? isArchived,
  }) async {
    try {
      final res = await _client.dio.put('/sessions/$id', data: {
        'title': ?title,
        'context_prompt': ?contextPrompt,
        'is_archived': ?isArchived,
      });
      return ChatSession.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _client.dio.delete('/sessions/$id');
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }
}
