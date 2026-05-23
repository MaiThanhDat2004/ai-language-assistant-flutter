class ChatSession {
  final String id;
  final String userId;
  final String? templateId;
  final String title;
  final String responseLanguage;
  final String? contextPrompt;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int messageCount;

  const ChatSession({
    required this.id,
    required this.userId,
    this.templateId,
    required this.title,
    required this.responseLanguage,
    this.contextPrompt,
    required this.isArchived,
    required this.createdAt,
    required this.updatedAt,
    required this.messageCount,
  });

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: json['id'] as String,
        userId: json['user_id'].toString(),
        templateId: json['template_id'] as String?,
        title: json['title'] as String? ?? 'Hội thoại mới',
        responseLanguage: json['response_language'] as String? ?? 'vi',
        contextPrompt: json['context_prompt'] as String?,
        isArchived: json['is_archived'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        messageCount: json['message_count'] as int? ?? 0,
      );
}
