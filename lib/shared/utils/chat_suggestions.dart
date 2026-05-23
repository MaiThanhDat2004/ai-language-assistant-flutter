// Gợi ý câu mở đầu cho chat empty state — context-aware theo tiêu đề
// session + ngôn ngữ trả lời. Khớp theo keyword tiếng Việt + tiếng Anh.
// Trả về tối đa 4 câu phù hợp. Nếu không match topic nào → fallback
// generic theo langCode.

List<String> suggestionsForSession({
  required String title,
  required String langCode,
}) {
  final t = title.toLowerCase();
  final lang = langCode.toLowerCase();

  // Topic-specific theo title — ưu tiên match keyword cụ thể trước
  if (t.contains('cà phê') || t.contains('coffee')) {
    return _t({
      'en': [
        "I'd like a latte, please",
        "Do you have oat milk?",
        "How much is a cappuccino?",
        "Can I get it iced?",
      ],
      'vi': [
        'Cho tôi một ly cà phê sữa',
        'Có sữa hạnh nhân không?',
        'Một ly cappuccino bao nhiêu?',
        'Cho đá nhé',
      ],
    }, lang);
  }
  if (t.contains('khám') || t.contains('bệnh') || t.contains('doctor')) {
    return _t({
      'en': [
        "I have a headache",
        "I've been feeling dizzy",
        "Can you prescribe something?",
        "How long until I recover?",
      ],
      'vi': [
        'Tôi bị đau đầu',
        'Tôi thấy chóng mặt',
        'Bác sĩ kê đơn thuốc giúp tôi',
        'Bao lâu thì khỏi?',
      ],
    }, lang);
  }
  if (t.contains('phỏng vấn') || t.contains('interview')) {
    return _t({
      'en': [
        'Tell me about yourself',
        "What's your greatest strength?",
        'Why did you leave your last job?',
        'Where do you see yourself in 5 years?',
      ],
      'vi': [
        'Hãy giới thiệu về bản thân',
        'Điểm mạnh của bạn là gì?',
        'Vì sao bạn nghỉ việc cũ?',
        '5 năm tới bạn muốn ở đâu?',
      ],
    }, lang);
  }
  if (t.contains('du lịch') ||
      t.contains('travel') ||
      t.contains('sân bay') ||
      t.contains('bay')) {
    return _t({
      'en': [
        "I'd like to check in for my flight",
        'Where is gate B12?',
        'Is the flight delayed?',
        'Can I have an aisle seat?',
      ],
      'vi': [
        'Tôi muốn check-in chuyến bay',
        'Cổng B12 ở đâu?',
        'Chuyến bay có bị hoãn không?',
        'Cho tôi ghế gần lối đi',
      ],
    }, lang);
  }
  if (t.contains('họp') || t.contains('meeting') || t.contains('công việc')) {
    return _t({
      'en': [
        "Let's start with the agenda",
        'Could you share your screen?',
        'Any updates from last week?',
        'When is the deadline?',
      ],
      'vi': [
        'Mình bắt đầu với agenda nhé',
        'Bạn share màn hình giúp',
        'Tuần trước có cập nhật gì không?',
        'Deadline là khi nào?',
      ],
    }, lang);
  }
  if (t.contains('mua') || t.contains('shop')) {
    return _t({
      'en': [
        'Do you have this in a smaller size?',
        'How much is this?',
        'Can I try it on?',
        'Is there any discount?',
      ],
      'vi': [
        'Có size nhỏ hơn không?',
        'Cái này bao nhiêu?',
        'Tôi mặc thử được không?',
        'Có giảm giá không?',
      ],
    }, lang);
  }
  if (t.contains('nhà hàng') || t.contains('đặt món') || t.contains('food')) {
    return _t({
      'en': [
        "What do you recommend?",
        "I'd like the steak, medium rare",
        "Can I see the menu, please?",
        "Could we get the bill?",
      ],
      'vi': [
        'Anh/chị gợi ý món gì?',
        'Cho tôi bít tết tái',
        'Cho xem menu nhé',
        'Tính tiền giúp',
      ],
    }, lang);
  }

  // Template-specific (theo template name từ DB)
  if (t.contains('ngữ pháp') || t.contains('grammar')) {
    return [
      'Sửa giúp tôi câu này',
      'Phân biệt "a" và "an" như nào?',
      'Khi nào dùng thì hiện tại hoàn thành?',
      'Câu bị động dùng ra sao?',
    ];
  }
  if (t.contains('dịch') || t.contains('translat')) {
    return [
      'Dịch câu sau sang tiếng Anh',
      'Cụm từ này nghĩa là gì?',
      'Dịch tự nhiên hơn cho tôi',
      'Đây có phải idiom không?',
    ];
  }
  if (t.contains('từ vựng') || t.contains('vocab')) {
    return [
      'Hôm nay học 5 từ mới chủ đề gì?',
      'Cho ví dụ với từ "resilient"',
      'Synonym của "happy"?',
      'Từ nào hay dùng trong văn nói?',
    ];
  }
  if (t.contains('phát âm') || t.contains('pronunciation')) {
    return [
      'Tôi đọc thử "comfortable"',
      'Sửa âm /θ/ cho tôi',
      'Phân biệt /iː/ và /ɪ/',
      'Câu này nhấn ở đâu?',
    ];
  }
  if (t.contains('thành ngữ') || t.contains('idiom')) {
    return [
      'Giải thích "break a leg"',
      'Idiom về thời gian',
      '"Spill the beans" nghĩa là gì?',
      'Idiom trong tiếng Việt tương ứng?',
    ];
  }
  if (t.contains('viết') || t.contains('write') || t.contains('văn')) {
    return [
      'Sửa đoạn này hay hơn',
      'Mở bài cho topic này',
      'Cách kết bài hấp dẫn',
      'Đoạn này có lỗi gì?',
    ];
  }
  if (t.contains('đọc hiểu') || t.contains('reading')) {
    return [
      'Tóm tắt bài này',
      'Đoạn này nói gì?',
      'Từ "X" trong bài nghĩa là gì?',
      'Ý chính tác giả là gì?',
    ];
  }
  if (t.contains('nhập vai') || t.contains('role')) {
    return [
      'Bắt đầu nhập vai nhé',
      'Đặt câu hỏi cho tôi',
      'Đổi tình huống khó hơn',
      'Sửa lỗi của tôi khi nói',
    ];
  }
  if (t.contains('luyện chính tả') || t.contains('spelling')) {
    return [
      'Cho tôi 5 từ để chính tả',
      'Đọc chậm để tôi viết',
      'Sửa lỗi chính tả của tôi',
      'Từ khó nhất hôm nay là gì?',
    ];
  }

  // Fallback theo language
  return _t({
    'en': [
      "Hi! Let's start chatting",
      "Help me practice English",
      "Can you ask me a question?",
      "Tell me an interesting fact",
    ],
    'ja': [
      'こんにちは！話しましょう',
      '簡単な質問してください',
      '日本語を練習したい',
      '何か面白い話を',
    ],
    'ko': [
      '안녕하세요! 대화 시작해요',
      '한국어 연습하고 싶어요',
      '질문 하나 해주세요',
      '재미있는 이야기 해주세요',
    ],
    'zh': [
      '你好！开始聊吧',
      '帮我练中文',
      '问我一个问题',
      '说个有趣的事',
    ],
    'fr': [
      'Bonjour ! Commençons',
      "Aide-moi à pratiquer le français",
      'Pose-moi une question',
      'Raconte-moi quelque chose',
    ],
    'es': [
      '¡Hola! Empecemos',
      'Ayúdame a practicar español',
      'Hazme una pregunta',
      'Cuéntame algo interesante',
    ],
    'de': [
      'Hallo! Lass uns anfangen',
      'Hilf mir, Deutsch zu üben',
      'Stell mir eine Frage',
      'Erzähl mir etwas',
    ],
    'vi': [
      'Chào bạn! Bắt đầu nào',
      'Giúp tôi luyện hội thoại',
      'Hỏi tôi một câu',
      'Kể chuyện gì hay đi',
    ],
  }, lang);
}

List<String> _t(Map<String, List<String>> m, String lang) {
  return m[lang] ?? m['en'] ?? m.values.first;
}
