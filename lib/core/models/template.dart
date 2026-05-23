class Template {
  final String id;
  final String name;
  final String? description;
  final String systemPrompt;
  final String defaultResponseLanguage;
  final String? category;
  final bool isSystem;
  final bool isFavorite;
  final DateTime createdAt;

  const Template({
    required this.id,
    required this.name,
    this.description,
    required this.systemPrompt,
    required this.defaultResponseLanguage,
    this.category,
    required this.isSystem,
    required this.isFavorite,
    required this.createdAt,
  });

  factory Template.fromJson(Map<String, dynamic> json) => Template(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        systemPrompt: json['system_prompt'] as String? ?? '',
        defaultResponseLanguage:
            json['default_response_language'] as String? ?? 'vi',
        category: json['category'] as String?,
        isSystem: json['is_system'] as bool? ?? false,
        isFavorite: json['is_favorite'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
