enum MessageRole { user, assistant }

enum MessageInputType { text, voice }

class ChatMessage {
  final String id;
  final String sessionId;
  final MessageRole role;
  final String content;
  final MessageInputType inputType;
  final String? audioUrl;
  final String? modelUsed;
  final int? tokenCount;
  // Contract enforcement metrics — hiển thị badge khi cần
  final String? languageDetected;
  final int languageRetryCount;
  final String? refusalReason; // 'off_scope' | 'language_drift' | null
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.inputType,
    this.audioUrl,
    this.modelUsed,
    this.tokenCount,
    this.languageDetected,
    this.languageRetryCount = 0,
    this.refusalReason,
    required this.createdAt,
  });

  bool get isUser => role == MessageRole.user;
  bool get isRefusal => refusalReason != null;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        sessionId: json['session_id'] as String,
        role: (json['role'] as String?) == 'user'
            ? MessageRole.user
            : MessageRole.assistant,
        content: json['content'] as String? ?? '',
        inputType: (json['input_type'] as String?) == 'voice'
            ? MessageInputType.voice
            : MessageInputType.text,
        audioUrl: json['audio_url'] as String?,
        modelUsed: json['model_used'] as String?,
        tokenCount: json['token_count'] as int?,
        languageDetected: json['language_detected'] as String?,
        languageRetryCount: (json['language_retry_count'] as int?) ?? 0,
        refusalReason: json['refusal_reason'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class ChatTurn {
  final ChatMessage userMessage;
  final ChatMessage assistantMessage;
  final double responseTimeMs;
  final String modelUsed;

  const ChatTurn({
    required this.userMessage,
    required this.assistantMessage,
    required this.responseTimeMs,
    required this.modelUsed,
  });

  factory ChatTurn.fromJson(Map<String, dynamic> json) => ChatTurn(
        userMessage:
            ChatMessage.fromJson(json['user_message'] as Map<String, dynamic>),
        assistantMessage: ChatMessage.fromJson(
            json['assistant_message'] as Map<String, dynamic>),
        responseTimeMs: (json['response_time_ms'] as num?)?.toDouble() ?? 0,
        modelUsed: json['model_used'] as String? ?? '',
      );
}
