import '../../core/models/session.dart';

/// Best-effort map title của session → emoji theo chủ đề. Áp dụng khi UI
/// muốn icon trực quan thay vì chat_bubble generic. Match theo keyword
/// tiếng Việt + tiếng Anh nên cover được cả Quick Start lẫn template tự tạo.
String emojiForSessionTitle(String title) {
  final t = title.toLowerCase();
  // Thứ tự match — keyword cụ thể đặt trước, generic đặt sau
  const map = <List<String>, String>{
    ['cà phê', 'coffee', 'tea', 'trà']: '☕',
    ['khám', 'bệnh', 'doctor', 'hospital', 'bác sĩ']: '🏥',
    ['phỏng vấn', 'interview', 'hr']: '🎓',
    ['du lịch', 'travel', 'sân bay', 'airport', 'bay', 'flight']: '✈️',
    ['họp', 'meeting', 'công việc', 'office', 'work']: '💼',
    ['mua sắm', 'mua', 'shop', 'cửa hàng', 'store']: '🛍️',
    ['nhà hàng', 'đặt món', 'restaurant', 'food', 'ăn']: '🍔',
    ['giới thiệu', 'introduce', 'self-intro']: '👋',
    ['từ vựng', 'vocabulary', 'vocab', 'từ mới']: '📚',
    ['dịch', 'translate', 'translation']: '🌐',
    ['phát âm', 'pronunciation', 'speaking', 'nói']: '🎙️',
    ['ngữ pháp', 'grammar']: '✍️',
    ['viết', 'write', 'writing', 'biên tập', 'editor']: '📝',
    ['nhập vai', 'role play', 'roleplay']: '🎭',
    ['hội thoại', 'conversation', 'free chat', 'chat']: '💬',
  };
  for (final entry in map.entries) {
    for (final kw in entry.key) {
      if (t.contains(kw)) return entry.value;
    }
  }
  return '💬';
}

/// Emoji cờ theo language code (ISO 639-1). Trả empty nếu không match.
String flagForLanguageCode(String code) {
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
      return '🇨🇳';
    case 'fr':
      return '🇫🇷';
    case 'de':
      return '🇩🇪';
    case 'es':
      return '🇪🇸';
    case 'it':
      return '🇮🇹';
    case 'pt':
      return '🇵🇹';
    case 'ru':
      return '🇷🇺';
    case 'th':
      return '🇹🇭';
    case 'id':
      return '🇮🇩';
    default:
      return '🌐';
  }
}

String emojiForSession(ChatSession s) => emojiForSessionTitle(s.title);
