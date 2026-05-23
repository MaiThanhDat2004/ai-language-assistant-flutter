import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../errors/app_error.dart';
import 'api_client.dart';

class STTResult {
  final String text;
  final String? languageDetected;

  const STTResult({required this.text, this.languageDetected});
}

/// Một từ trong kết quả chấm phát âm.
class PronunciationWord {
  final String? ref;
  final String? got;
  /// 'match' | 'wrong' | 'missing' | 'extra'
  final String status;
  /// Whisper word-level confidence — 0.0-1.0, null nếu không có audio cho từ này.
  /// < 0.7 = phát âm chưa rõ.
  final double? confidence;
  const PronunciationWord({
    this.ref,
    this.got,
    required this.status,
    this.confidence,
  });
  factory PronunciationWord.fromJson(Map<String, dynamic> j) => PronunciationWord(
        ref: j['ref'] as String?,
        got: j['got'] as String?,
        status: j['status'] as String? ?? 'match',
        confidence: (j['confidence'] as num?)?.toDouble(),
      );

  /// True nếu Whisper không chắc về cách phát âm từ này (probability < 0.7).
  bool get isLowConfidence =>
      confidence != null && confidence! < 0.7 && (status == 'match' || status == 'extra');
}

class PronunciationResult {
  final String? attemptId;
  final double score;
  /// 'good' | 'fair' | 'needs_work'
  final String rating;
  final String transcription;
  final String reference;
  final List<PronunciationWord> words;
  final List<String> wrongWords;

  const PronunciationResult({
    this.attemptId,
    required this.score,
    required this.rating,
    required this.transcription,
    required this.reference,
    required this.words,
    required this.wrongWords,
  });

  factory PronunciationResult.fromJson(Map<String, dynamic> j) =>
      PronunciationResult(
        attemptId: j['attempt_id'] as String?,
        score: (j['score'] as num).toDouble(),
        rating: j['rating'] as String? ?? 'needs_work',
        transcription: j['transcription'] as String? ?? '',
        reference: j['reference'] as String? ?? '',
        words: (j['words'] as List? ?? [])
            .map((e) => PronunciationWord.fromJson(e as Map<String, dynamic>))
            .toList(),
        wrongWords:
            (j['wrong_words'] as List? ?? []).map((e) => e as String).toList(),
      );
}

/// Một attempt lưu trong lịch sử /audio/pronunciation/history
class PronunciationAttempt {
  final String id;
  final String referenceText;
  final String transcription;
  final double score;
  final String rating;
  final String? language;
  final List<String> wrongWords;
  final List<PronunciationWord> words;
  final DateTime createdAt;

  const PronunciationAttempt({
    required this.id,
    required this.referenceText,
    required this.transcription,
    required this.score,
    required this.rating,
    this.language,
    required this.wrongWords,
    required this.words,
    required this.createdAt,
  });

  factory PronunciationAttempt.fromJson(Map<String, dynamic> j) =>
      PronunciationAttempt(
        id: j['id'] as String,
        referenceText: j['reference_text'] as String? ?? '',
        transcription: j['transcription'] as String? ?? '',
        score: (j['score'] as num).toDouble(),
        rating: j['rating'] as String? ?? 'needs_work',
        language: j['language'] as String?,
        wrongWords: (j['wrong_words'] as List? ?? [])
            .map((e) => e as String)
            .toList(),
        words: (j['words'] as List? ?? [])
            .map((e) => PronunciationWord.fromJson(e as Map<String, dynamic>))
            .toList(),
        createdAt:
            DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}

class PronunciationStats {
  final int totalAttempts;
  final double avgScoreWeek;
  final double bestScore;
  final int streakDays;
  final Map<String, int> byLanguage;

  const PronunciationStats({
    required this.totalAttempts,
    required this.avgScoreWeek,
    required this.bestScore,
    required this.streakDays,
    required this.byLanguage,
  });

  factory PronunciationStats.fromJson(Map<String, dynamic> j) =>
      PronunciationStats(
        totalAttempts: (j['total_attempts'] as num).toInt(),
        avgScoreWeek: (j['avg_score_week'] as num).toDouble(),
        bestScore: (j['best_score'] as num).toDouble(),
        streakDays: (j['streak_days'] as num).toInt(),
        byLanguage: ((j['by_language'] as Map?) ?? {}).map(
          (k, v) => MapEntry(k as String, (v as num).toInt()),
        ),
      );
}

class PronunciationCoachingItem {
  final String word;
  final String phoneme;    // IPA hoặc mô tả ngắn ("/θ/", "âm tr")
  final String heardAs;    // Whisper nghe user đọc thành gì
  final String context;    // ảnh hưởng nghĩa trong CÂU NÀY
  final String kind;       // "wrong" | "missing" | "unclear"
  final String tongue;     // vị trí + cử động lưỡi
  final String lips;       // khẩu hình môi
  final String airflow;    // cách thở/dùng thanh quản
  final String tip;        // mẹo luyện cụ thể

  const PronunciationCoachingItem({
    required this.word,
    required this.phoneme,
    required this.heardAs,
    required this.context,
    required this.kind,
    required this.tongue,
    required this.lips,
    required this.airflow,
    required this.tip,
  });

  factory PronunciationCoachingItem.fromJson(Map<String, dynamic> j) =>
      PronunciationCoachingItem(
        word: (j['word'] as String?) ?? '',
        phoneme: (j['phoneme'] as String?) ?? '—',
        heardAs: (j['heard_as'] as String?) ?? '',
        context: (j['context'] as String?) ?? '',
        kind: (j['kind'] as String?) ?? 'wrong',
        tongue: (j['tongue'] as String?) ?? '',
        lips: (j['lips'] as String?) ?? '',
        airflow: (j['airflow'] as String?) ?? '',
        tip: (j['tip'] as String?) ?? '',
      );
}

class PronunciationCoaching {
  final String summary;
  final List<PronunciationCoachingItem> items;

  const PronunciationCoaching({
    required this.summary,
    required this.items,
  });

  factory PronunciationCoaching.fromJson(Map<String, dynamic> j) =>
      PronunciationCoaching(
        summary: (j['summary'] as String?) ?? '',
        items: ((j['items'] as List?) ?? [])
            .map((e) =>
                PronunciationCoachingItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class AudioApi {
  final ApiClient _client;

  AudioApi(this._client);

  /// STT từ file path (dùng cho mobile/desktop).
  Future<STTResult> speechToText({
    required String filePath,
    String? language,
  }) async {
    try {
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
        'language': ?language,
      });
      return _postSTT(form);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  /// STT từ bytes (dùng cho web — không có filePath thật, chỉ có blob/Uint8List).
  Future<STTResult> speechToTextFromBytes({
    required Uint8List bytes,
    required String filename,
    String? language,
  }) async {
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
        'language': ?language,
      });
      return _postSTT(form);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  Future<STTResult> _postSTT(FormData form) async {
    final res = await _client.dio.post(
      '/audio/stt',
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );
    final data = res.data as Map<String, dynamic>;
    return STTResult(
      text: data['text'] as String? ?? '',
      languageDetected: data['language_detected'] as String?,
    );
  }

  Future<Uint8List> textToSpeech({
    required String text,
    String languageCode = 'vi',
    bool slow = false,
  }) async {
    try {
      final res = await _client.dio.post(
        '/audio/tts',
        data: {
          'text': text,
          'language_code': languageCode,
          'slow': slow,
        },
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(res.data as List<int>);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  /// Chấm phát âm: gửi audio user vừa thu + reference text → score + chữ sai.
  /// Path version (mobile/desktop).
  Future<PronunciationResult> scorePronunciation({
    required String filePath,
    required String referenceText,
    String? language,
    String? sessionId,
    String? messageId,
  }) async {
    try {
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
        'reference_text': referenceText,
        'language': ?language,
        'session_id': ?sessionId,
        'message_id': ?messageId,
      });
      return _postPronunciation(form);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  /// Bytes version (web — blob/Uint8List).
  Future<PronunciationResult> scorePronunciationFromBytes({
    required Uint8List bytes,
    required String filename,
    required String referenceText,
    String? language,
    String? sessionId,
    String? messageId,
  }) async {
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
        'reference_text': referenceText,
        'language': ?language,
        'session_id': ?sessionId,
        'message_id': ?messageId,
      });
      return _postPronunciation(form);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  Future<PronunciationResult> _postPronunciation(FormData form) async {
    final res = await _client.dio.post(
      '/audio/pronunciation',
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );
    return PronunciationResult.fromJson(res.data as Map<String, dynamic>);
  }

  /// List lịch sử attempts của user, mới nhất trước.
  Future<List<PronunciationAttempt>> listPronunciationHistory({
    String? language,
    int limit = 30,
    int offset = 0,
  }) async {
    try {
      final res = await _client.dio.get(
        '/audio/pronunciation/history',
        queryParameters: {
          'language': ?language,
          'limit': limit,
          'offset': offset,
        },
      );
      final data = res.data;
      final List items =
          data is List ? data : (data['items'] as List? ?? []);
      return items
          .map((e) => PronunciationAttempt.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  /// Tổng quan tiến độ phát âm (header Pronunciation screen).
  Future<PronunciationStats> getPronunciationStats() async {
    try {
      final res = await _client.dio.get('/audio/pronunciation/stats');
      return PronunciationStats.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  /// Sinh hướng dẫn phát âm chi tiết (lưỡi/môi/hơi thở) cho các từ sai.
  /// Backend dùng LLM (gemma2:2b) gen JSON — có cache trong process.
  Future<PronunciationCoaching> getPronunciationCoaching({
    required String referenceText,
    required String transcription,
    required List<String> wrongWords,
    required String language,
  }) async {
    try {
      final res = await _client.dio.post(
        '/audio/pronunciation/coach',
        data: {
          'reference_text': referenceText,
          'transcription': transcription,
          'wrong_words': wrongWords,
          'language': language,
        },
      );
      return PronunciationCoaching.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }
}
