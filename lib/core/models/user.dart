class User {
  final String id;
  final String username;
  final String email;
  final String? fullName;
  final String? avatarUrl;
  final String? preferredLanguage;
  final bool isActive;
  final DateTime? lastLoginAt;
  final DateTime createdAt;

  const User({
    required this.id,
    required this.username,
    required this.email,
    this.fullName,
    this.avatarUrl,
    this.preferredLanguage,
    required this.isActive,
    this.lastLoginAt,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        username: json['username'] as String,
        email: json['email'] as String,
        fullName: json['full_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        preferredLanguage: json['preferred_language'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        lastLoginAt: json['last_login_at'] != null
            ? DateTime.parse(json['last_login_at'] as String)
            : null,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class AuthTokens {
  final String accessToken;
  final String refreshToken;
  final String userId;
  final String username;
  final int expiresIn;

  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.username,
    required this.expiresIn,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        userId: json['user_id'].toString(),
        username: json['username'] as String,
        expiresIn: json['expires_in'] as int? ?? 3600,
      );
}
