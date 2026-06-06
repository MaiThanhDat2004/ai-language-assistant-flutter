import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../errors/app_error.dart';
import '../models/message.dart';
import 'api_client.dart';

/// Sự kiện stream từ backend (SSE).
sealed class ChatStreamEvent {
  const ChatStreamEvent();
}

class ChatStreamIntent extends ChatStreamEvent {
  final bool inScope;
  final String method;
  final String reason;
  const ChatStreamIntent({
    required this.inScope,
    required this.method,
    required this.reason,
  });
}

class ChatStreamToken extends ChatStreamEvent {
  final String content;
  const ChatStreamToken(this.content);
}

class ChatStreamDone extends ChatStreamEvent {
  final String userMessageId;
  final String assistantMessageId;
  final double responseTimeMs;
  final String? modelUsed;
  const ChatStreamDone({
    required this.userMessageId,
    required this.assistantMessageId,
    required this.responseTimeMs,
    this.modelUsed,
  });
}

class ChatStreamError extends ChatStreamEvent {
  final String error;
  const ChatStreamError(this.error);
}

class ChatApi {
  final ApiClient _client;

  ChatApi(this._client);

  Future<ChatTurn> send({
    required String sessionId,
    required String content,
    String inputType = 'text',
    String? audioUrl,
  }) async {
    try {
      final res = await _client.dio.post('/chat/', data: {
        'session_id': sessionId,
        'content': content,
        'input_type': inputType,
        'audio_url': ?audioUrl,
      });
      return ChatTurn.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  /// Stream chat response token-by-token qua SSE.
  ///
  /// Yield mỗi event mới (intent → tokens → done). Tự đóng stream khi gặp
  /// "done" hoặc "error". Caller wire vào UI để render từng token mượt mà.
  Stream<ChatStreamEvent> sendStream({
    required String sessionId,
    required String content,
    String inputType = 'text',
    String? audioUrl,
  }) async* {
    final response = await _client.dio.post<ResponseBody>(
      '/chat/stream',
      data: {
        'session_id': sessionId,
        'content': content,
        'input_type': inputType,
        'audio_url': ?audioUrl,
      },
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Accept': 'text/event-stream'},
      ),
    );

    final body = response.data;
    if (body == null) {
      yield const ChatStreamError('Empty stream body');
      return;
    }

    // SSE format: mỗi event là 1 hoặc nhiều dòng "data: <json>" rồi 1 dòng trống.
    // Buffer các byte tới khi gặp "\n\n" thì parse.
    final buffer = StringBuffer();
    await for (final chunkBytes in body.stream) {
      buffer.write(utf8.decode(chunkBytes, allowMalformed: true));
      while (true) {
        final str = buffer.toString();
        final idx = str.indexOf('\n\n');
        if (idx < 0) break;
        final block = str.substring(0, idx);
        final rest = str.substring(idx + 2);
        buffer
          ..clear()
          ..write(rest);

        // Parse dòng data: ...
        for (final line in block.split('\n')) {
          if (!line.startsWith('data:')) continue;
          final json = line.substring(5).trim();
          if (json.isEmpty) continue;
          try {
            final evt = jsonDecode(json) as Map<String, dynamic>;
            final type = evt['type'] as String?;
            switch (type) {
              case 'intent':
                yield ChatStreamIntent(
                  inScope: evt['in_scope'] as bool? ?? true,
                  method: evt['method'] as String? ?? '',
                  reason: evt['reason'] as String? ?? '',
                );
              case 'token':
                yield ChatStreamToken(evt['content'] as String? ?? '');
              case 'done':
                yield ChatStreamDone(
                  userMessageId: evt['user_message_id'] as String? ?? '',
                  assistantMessageId:
                      evt['assistant_message_id'] as String? ?? '',
                  responseTimeMs:
                      ((evt['response_time_ms'] as num?) ?? 0).toDouble(),
                  modelUsed: evt['model_used'] as String?,
                );
                return;
              case 'error':
                yield ChatStreamError(evt['error'] as String? ?? 'unknown');
                return;
            }
          } catch (_) {
            // Bỏ qua line không parse được
          }
        }
      }
    }
  }

  Future<List<ChatMessage>> getMessages(
    String sessionId, {
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final res = await _client.dio.get(
        '/chat/$sessionId/messages',
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final data = res.data;
      final List items =
          data is List ? data : (data['items'] as List? ?? []);
      return items
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  /// Layer 4 — Grammar correction. Lazy fetch sau khi AI stream xong với
  /// user_message_id. Backend cache 2 tầng (FIFO mem + DB column) nên lần
  /// sau load history sẽ trả ngay không gọi LLM.
  Future<MessageCorrection> getCorrection(String userMessageId) async {
    try {
      final res =
          await _client.dio.post('/chat/correction/$userMessageId');
      return MessageCorrection.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }
}

// ============================================================
// Layer 4 — Grammar Correction model
// ============================================================

class CorrectionSegment {
  /// 'keep' | 'remove' | 'add'
  final String type;
  final String text;
  const CorrectionSegment({required this.type, required this.text});

  factory CorrectionSegment.fromJson(Map<String, dynamic> json) =>
      CorrectionSegment(
        type: json['type'] as String? ?? 'keep',
        text: json['text'] as String? ?? '',
      );

  bool get isKeep => type == 'keep';
  bool get isRemove => type == 'remove';
  bool get isAdd => type == 'add';
}

class MessageCorrection {
  final bool hasError;
  final String wrong;
  final String corrected;
  final List<CorrectionSegment> diff;
  final String explanation;
  // 3 câu USER có thể nói tiếp dựa vào AI response. Câu đầu thường là
  // phiên bản đã sửa nếu hasError=true (để user practice).
  final List<String> nextSuggestions;

  const MessageCorrection({
    required this.hasError,
    required this.wrong,
    required this.corrected,
    required this.diff,
    required this.explanation,
    required this.nextSuggestions,
  });

  factory MessageCorrection.fromJson(Map<String, dynamic> json) {
    final rawDiff = json['diff'] as List? ?? [];
    final rawSuggestions = json['next_suggestions'] as List? ?? [];
    return MessageCorrection(
      hasError: json['has_error'] as bool? ?? false,
      wrong: json['wrong'] as String? ?? '',
      corrected: json['corrected'] as String? ?? '',
      diff: rawDiff
          .map((e) =>
              CorrectionSegment.fromJson(e as Map<String, dynamic>))
          .toList(),
      explanation: json['explanation'] as String? ?? '',
      nextSuggestions:
          rawSuggestions.map((e) => e.toString()).toList(),
    );
  }
}
