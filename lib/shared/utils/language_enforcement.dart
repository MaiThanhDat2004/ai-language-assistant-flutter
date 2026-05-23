// Câu lệnh ép ngôn ngữ trả lời — viết bằng chính ngôn ngữ đích để model
// dễ "khoá" output vào ngôn ngữ đó từ đầu. Bổ sung cho Layer 1 langdetect
// retry của backend (gemma2:2b 2B params đôi khi bias sang English với
// chủ đề tiếng Anh học thuật như "phân biệt a vs an").
//
// Why prepend bằng chính ngôn ngữ đích: Model nhỏ phản ứng tốt hơn với
// instruction trong target language hơn là instruction English nói "respond
// in X". Đã verify qua HTTP smoke test P18 cho 12 ngôn ngữ.

String languageEnforcement(String langCode) {
  switch (langCode.toLowerCase()) {
    case 'vi':
      return 'QUAN TRỌNG: Hãy trả lời TOÀN BỘ bằng tiếng Việt. '
          'Kể cả khi giải thích về ngôn ngữ khác, phần giải thích vẫn phải bằng tiếng Việt. '
          'Ví dụ từ vựng tiếng nước ngoài thì giữ nguyên, '
          'nhưng định nghĩa, hướng dẫn và bình luận đều dùng tiếng Việt.';
    case 'en':
      return 'IMPORTANT: Respond entirely in English. '
          'Even when explaining other languages, the explanation itself must be in English.';
    case 'ja':
      return '重要：必ず日本語で答えてください。'
          '他の言語について説明する場合でも、説明文は日本語で書いてください。';
    case 'ko':
      return '중요: 반드시 한국어로 답변해 주세요. '
          '다른 언어를 설명할 때에도 설명은 한국어로 작성해 주세요.';
    case 'zh':
      return '重要：请全部用中文回答。'
          '即使在解释其他语言时，解释也必须用中文书写。';
    case 'fr':
      return 'IMPORTANT : Réponds entièrement en français. '
          "Même lorsque tu expliques d'autres langues, l'explication doit être en français.";
    case 'es':
      return 'IMPORTANTE: Responde completamente en español. '
          'Incluso al explicar otros idiomas, la explicación debe estar en español.';
    case 'de':
      return 'WICHTIG: Antworte vollständig auf Deutsch. '
          'Auch wenn du andere Sprachen erklärst, muss die Erklärung auf Deutsch sein.';
    case 'it':
      return 'IMPORTANTE: Rispondi interamente in italiano. '
          'Anche quando spieghi altre lingue, la spiegazione stessa deve essere in italiano.';
    case 'pt':
      return 'IMPORTANTE: Responda inteiramente em português. '
          'Mesmo ao explicar outros idiomas, a explicação em si deve estar em português.';
    case 'ru':
      return 'ВАЖНО: Отвечайте полностью на русском языке. '
          'Даже при объяснении других языков, само объяснение должно быть на русском.';
    case 'th':
      return 'สำคัญ: กรุณาตอบเป็นภาษาไทยทั้งหมด '
          'แม้แต่เวลาอธิบายภาษาอื่น คำอธิบายก็ต้องเป็นภาษาไทย';
    default:
      return 'IMPORTANT: Respond entirely in the requested language ($langCode).';
  }
}

/// Combine instruction ép ngôn ngữ với role-play prompt (nếu có).
/// Instruction language enforcement đặt TRƯỚC để model gặp đầu tiên.
String buildContextPrompt({
  required String langCode,
  String? rolePlay,
}) {
  final lang = languageEnforcement(langCode);
  if (rolePlay == null || rolePlay.trim().isEmpty) return lang;
  return '$lang\n\n$rolePlay';
}
