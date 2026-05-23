import 'package:dio/dio.dart';
import '../errors/app_error.dart';
import '../models/vocabulary.dart';
import 'api_client.dart';

class VocabularyApi {
  final ApiClient _client;

  VocabularyApi(this._client);

  Future<Vocabulary> create({
    required String word,
    required String language,
    String? definition,
    String? example,
    String? notes,
    String? sourceMessageId,
    bool autoGenerate = true,
  }) async {
    try {
      final res = await _client.dio.post('/vocabulary/', data: {
        'word': word,
        'language': language,
        'definition': ?definition,
        'example': ?example,
        'notes': ?notes,
        'source_message_id': ?sourceMessageId,
        'auto_generate': autoGenerate,
      });
      return Vocabulary.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  Future<List<Vocabulary>> list({String? language, int limit = 100}) async {
    try {
      final res = await _client.dio.get('/vocabulary/', queryParameters: {
        'language': ?language,
        'limit': limit,
      });
      final data = res.data;
      final List items =
          data is List ? data : (data['items'] as List? ?? []);
      return items
          .map((e) => Vocabulary.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _client.dio.delete('/vocabulary/$id');
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  /// Lấy các từ tới hạn ôn (next_review_at ≤ now()).
  Future<List<Vocabulary>> listDue({int limit = 20}) async {
    try {
      final res = await _client.dio.get('/vocabulary/due',
          queryParameters: {'limit': limit});
      final data = res.data;
      final List items =
          data is List ? data : (data['items'] as List? ?? []);
      return items
          .map((e) => Vocabulary.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  /// Chấm điểm 1 từ vừa ôn — server áp dụng SM-2 và trả vocab state mới.
  Future<Vocabulary> review(String id, ReviewRating rating) async {
    try {
      final res = await _client.dio.post(
        '/vocabulary/$id/review',
        data: {'rating': rating.name},
      );
      return Vocabulary.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  /// Tổng quan tiến độ ôn tập của user.
  Future<VocabStats> getStats() async {
    try {
      final res = await _client.dio.get('/vocabulary/stats');
      return VocabStats.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  /// AI tự trích xuất 3-5 từ "đáng học" từ 1 đoạn text.
  Future<List<VocabularyCandidate>> extract({
    required String text,
    required String sourceLanguage,
    String? sourceMessageId,
    int maxItems = 5,
  }) async {
    try {
      final res = await _client.dio.post('/vocabulary/extract', data: {
        'text': text,
        'source_language': sourceLanguage,
        'source_message_id': ?sourceMessageId,
        'max_items': maxItems,
      });
      final List items = (res.data as List?) ?? [];
      return items
          .map((e) =>
              VocabularyCandidate.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  /// Random N từ trong sổ tay — phục vụ Browse mode khi không có due.
  Future<List<Vocabulary>> listRandom({int limit = 20}) async {
    try {
      final res = await _client.dio.get('/vocabulary/random',
          queryParameters: {'limit': limit});
      final List items = (res.data as List?) ?? [];
      return items
          .map((e) => Vocabulary.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }
}
