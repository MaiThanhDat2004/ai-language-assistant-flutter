# AI Language Learning Assistant — Flutter Frontend

Ứng dụng Flutter cho hệ thống **Trợ lý Học Ngoại ngữ AI** — khóa luận tốt nghiệp K67-HTTT, ĐH Lâm Nghiệp.

Backend (FastAPI + PostgreSQL + Ollama): [Backend-AI-Assistant-Project](https://github.com/MaiThanhDat2004/Backend-AI-Assistant-Project)

## Tính năng chính

- 💬 **Chat đa ngôn ngữ** với streaming SSE token-by-token, 12 ngôn ngữ hỗ trợ
- 🎯 **Contract enforcement 3 lớp**: bảo đảm AI trả đúng ngôn ngữ và phạm vi học tập
- 🎙 **Voice Conversation Mode** — vòng STT → LLM → TTS với VAD silence detection
- 🗣 **Pronunciation scoring + coaching** — chấm điểm phát âm + gợi ý vị trí lưỡi/môi/hơi thở
- 📚 **Sổ tay từ vựng SM-2** — spaced repetition (Anki-style), self-test typing
- 🧠 **Cross-session vector memory** — AI nhớ lịch sử học qua nhiều phiên
- 🎨 **Bright/Dark theme** — Stitch design system
- 👤 **Avatar upload, profile, templates** với CEFR adaptation

## Stack

| Layer | Technology |
|---|---|
| Framework | Flutter 3.11+ / Dart |
| State | flutter_riverpod 2.5 |
| Routing | go_router 14 (auth-aware redirect) |
| HTTP | Dio 5 + refresh-token interceptor |
| Storage | flutter_secure_storage (web-fallback in-memory) |
| Audio | record + just_audio |
| Charts | fl_chart |
| Markdown | flutter_markdown |

## Cấu trúc thư mục

```
lib/
  core/
    api/         # ApiClient + 6 service classes (auth/sessions/chat/templates/languages/audio)
    audio/      # AudioPlayerService, VoiceRecorder
    auth/        # TokenStorage
    errors/      # AppError (parse error envelope từ backend)
    models/      # User, Session, Message, Template, Language
    router/      # go_router config
    theme/       # AppColors, AppTheme
  features/      # auth, home, chat, sessions, templates, vocabulary, pronunciation, profile
  shared/providers/  # Riverpod providers, AuthStateNotifier
```

## Backend URL theo platform

Cấu hình trong `lib/core/api/api_config.dart`:

- Web / Windows / macOS / iOS simulator: `http://localhost:8000`
- Android emulator: `http://10.0.2.2:8000`
- Thiết bị thật: đổi sang IP máy chạy backend

## Yêu cầu hệ thống

- Flutter SDK 3.11+
- Backend FastAPI chạy tại `http://localhost:8000` ([repo backend](https://github.com/MaiThanhDat2004/Backend-AI-Assistant-Project))
- Ollama với model `gemma2:2b` (1.6GB) — đủ cho dev trên máy 16GB RAM

## Chạy thử

```bash
flutter pub get
flutter run -d chrome      # hoặc -d windows / -d <android-device>
```

Phím tắt trong terminal `flutter run`:
- `R` (uppercase) — hot restart
- `q` — thoát

## Kiểm tra code

```bash
flutter analyze            # static analysis
dart fix --apply           # auto-fix lint warnings
```

## Đề tài khóa luận

**"Xây dựng Hệ thống Trợ lý Học Ngoại ngữ trên Thiết bị Di động dựa trên Mô hình Ngôn ngữ Lớn (LLM)"**

- Sinh viên: Mai Thành Đạt — K67-HTTT
- GVHD: ThS. Mai Hà An
- Trường: ĐH Lâm Nghiệp Việt Nam

**Đóng góp kỹ thuật**:
1. Contract enforcement 3-layer: langdetect + intent classifier (2-tier rule + LLM judge) + refusal generator
2. Metalingual bypass (Wittgenstein use/mention) — phân biệt object-level vs metalingual query
3. Multi-language coverage cho 12 ngôn ngữ ở Tier 1 (~5ms inference)
4. Cross-session vector memory với nomic-embed-text 768-dim
5. Pronunciation coaching qua articulatory phonetics (lưỡi/môi/hơi) sinh bởi LLM
