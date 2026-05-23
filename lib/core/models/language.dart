class Language {
  final String code;
  final String name;
  final String nativeName;

  const Language({
    required this.code,
    required this.name,
    required this.nativeName,
  });

  factory Language.fromJson(Map<String, dynamic> json) => Language(
        code: json['code'] as String,
        name: json['name'] as String,
        nativeName: json['native_name'] as String,
      );

  String get flag {
    switch (code.toLowerCase()) {
      case 'vi':
        return '🇻🇳';
      case 'en':
        return '🇬🇧';
      case 'ja':
        return '🇯🇵';
      case 'ko':
        return '🇰🇷';
      case 'zh':
      case 'zh-cn':
        return '🇨🇳';
      case 'fr':
        return '🇫🇷';
      case 'es':
        return '🇪🇸';
      case 'de':
        return '🇩🇪';
      case 'it':
        return '🇮🇹';
      case 'pt':
        return '🇵🇹';
      case 'ru':
        return '🇷🇺';
      case 'th':
        return '🇹🇭';
      default:
        return '🌐';
    }
  }
}
