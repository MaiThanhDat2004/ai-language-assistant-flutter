# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# AI Assistant Language — Flutter Frontend

App Flutter cho hệ thống Trợ lý Ngôn ngữ AI (brand name **DLanguage**). Giao tiếp với backend FastAPI (cùng máy).
Code Flutter nằm trong `flutter_application_1/` (KHÔNG ở root — các file `*.html` ở root + trong `flutter_application_1/` là mockup design canvas tham khảo, không build. Đã `.gitignore` `/*.html`).

## Stack
- **Flutter 3.11+** / Dart, light/dark theme toggle + Google Fonts **Be Vietnam Pro** (đẹp với tiếng Việt)
- **State**: flutter_riverpod 2.5
- **Routing**: go_router 14 với auth-aware redirect
- **HTTP**: Dio 5 + interceptor refresh token, in-memory fallback nếu secure storage fail trên web
- **Storage**: flutter_secure_storage (có fallback khi `OperationError`)
- **Audio**: record (thu) + just_audio (phát) — đã wire đầy đủ: voice conversation, chấm phát âm, TTS playback
- **Markdown**: flutter_markdown cho AI response
- **Charts**: fl_chart cho màn Stats / Pronunciation stats
- **Assets**: `assets/images/logo.png` (logo DLanguage — dùng trong splash, chat AppBar, AI bubble avatar, typing bubble)

## Cấu trúc
```
flutter_application_1/
  assets/images/        # logo.png (DLanguage)
  lib/
    core/
      api/         # ApiClient + 9 service: auth/sessions/chat/templates/languages/audio/vocabulary/stats
      audio/       # VoiceRecorder, AudioPlayerService (singleton qua Riverpod, có dispose)
      auth/        # TokenStorage (secure storage + in-memory fallback + themeMode persist)
      errors/      # AppError (parse {error: {code, message}} từ backend)
      models/      # User, Session, Message, Template, Language, Vocabulary, DashboardStats
                   #   (hand-written fromJson, KHÔNG dùng codegen dù pubspec có freezed/json_serializable)
      router/      # go_router với refresh listener
      theme/       # AppColors (Coral light palette + dynamic dark) + AppTheme (Be Vietnam Pro)
    features/      # auth, home, chat, sessions, templates, profile, vocabulary, stats, pronunciation
    shared/
      providers/   # app_providers.dart — TẤT CẢ Riverpod providers + AuthStateNotifier + ThemeModeNotifier + meProvider
      utils/       # language_enforcement (12 lang prepend prompt), chat_suggestions (context-aware), session_icon (emoji+flag)
      widgets/     # main_bottom_nav (5 tabs), language_picker_sheet (12 ngôn ngữ kèm cờ)
```
Các model audio (STTResult, PronunciationResult/Word/Attempt/Stats/Coaching) + MessageCorrection (Layer 4) định nghĩa inline trong `core/api/audio_api.dart` & `core/api/chat_api.dart`, không tách ra `models/`.

## Brand & Theme
- App name **DLanguage** (web title, AndroidManifest label, web manifest, splash heading)
- Theme **Coral light** chủ đạo: primary `#FF6B47`, navy `#181428`, bg `#F2F2F7`
- Dark variant: `#15121F` plum-near-black + cùng coral accent (xem `_dark` palette trong `app_colors.dart`)
- Logo: 80×80 splash, 36×36 chat AppBar, 32×32 message bubble avatar

## Backend
- **Đường dẫn local**: `D:\AI-Assistant-Project\backend_v2\`
- **Repo**: https://github.com/MaiThanhDat2004/Backend-AI-Assistant-Project
- **Stack**: FastAPI + PostgreSQL + JWT (access 60min, refresh 30 days) + Ollama / Gemini fallback
- **Base URL theo platform** (xem `core/api/api_config.dart`):
  - Web/Windows/macOS/iOS sim: `http://localhost:8000`
  - Android emulator: `http://10.0.2.2:8000`
- **CORS**: `.env` đặt `CORS_ORIGINS=*` cho dev

## ⚠️ Quy ước quan trọng (đã từng bị bug)

### 1. List endpoints trả về **List trực tiếp**, KHÔNG bọc trong `{items: [...]}`
Backend dùng `response_model=list[XxxResponse]`. Khi viết API service Flutter:

```dart
final data = res.data;
final List items = data is List ? data : (data['items'] as List? ?? []);
```

Áp dụng cho: `GET /sessions/`, `GET /templates/`, `GET /chat/{id}/messages`, `GET /languages/`.

### 2. Tên field backend
- Template create dùng `default_response_language` (KHÔNG phải `response_language`)
- Session create dùng `response_language` (đúng)
- Message dùng `input_type` ('text' | 'voice'), `role` ('user' | 'assistant')

### 3. Error envelope
Backend luôn trả lỗi dạng:
```json
{"error": {"code": "...", "message": "...", "details": ...}}
```
`AppError.fromDio` parse format này. Không tự ý đổi format error trên backend.

### 4. 502 = LLM tạm fail, retry-safe
Khi Ollama timeout/500, backend trả 502. App đã có message "Máy chủ AI tạm thời không phản hồi". User có thể bấm "Thử lại" trong SnackBar.

### 5. Timeouts
- `connectTimeout: 15s` — đủ cho LAN
- `receiveTimeout: 240s` — phải lớn vì Ollama CPU rất chậm với model 9b
- `sendTimeout: 60s` — chỉ ảnh hưởng upload audio
- Backend `.env` `OLLAMA_TIMEOUT=60.0` — model 2b dư, model 9b cần tăng

### 6. flutter_secure_storage trên web hay throw `OperationError`
`TokenStorage` đã có in-memory fallback. Đừng remove fallback — sẽ làm hỏng login trên web.

### 7. Router redirect — splash KHÔNG được tính là auth route
Khi `auth.isLoading=false`, nếu user vẫn ở splash → phải redirect sang `/home` (đã auth) hoặc `/welcome` (chưa). Auth routes = `/welcome`, `/login`, `/register`. Nếu coi splash là auth route như login/register, sẽ kẹt vĩnh viễn (đã từng bị).

### 8. Token refresh
- Interceptor trong `ApiClient` xử lý 401 → refresh → retry.
- Concurrent requests đang đợi sẽ queue qua `Completer`, sau refresh sẽ replay.
- Khi refresh fail (refresh token cũng hết hạn) → `onUnauthorized` callback → clear storage → router redirect login.
- Đừng thêm 401 handling thủ công ở từng API service — đã centralized.

### 9. Chat streaming SSE (`POST /chat/stream`)
- `ChatApi.sendStream` trả `Stream<ChatStreamEvent>` — sealed class: `ChatStreamIntent` → nhiều `ChatStreamToken` → `ChatStreamDone` (hoặc `ChatStreamError`). Stream tự đóng khi gặp `done`/`error`.
- Parse SSE thủ công: buffer byte tới khi gặp `\n\n`, mỗi block lấy dòng `data: <json>`. Đừng đổi sang lib SSE — Dio stream + parser này đã chạy ổn cho cả web lẫn desktop.
- Có cả `send()` (non-stream) làm fallback. UI chat dùng stream để render token mượt.

### 10. Grammar correction (Layer 4) — lazy, có cache 2 tầng
`ChatApi.getCorrection(userMessageId)` gọi `POST /chat/correction/{id}` SAU khi AI stream xong. Backend cache 2 tầng:
- **In-memory FIFO 500** trong `correction_service._CORRECTION_CACHE` (key gồm cả `ai_text[:100]` để suggestions match context)
- **DB column** `messages.correction_json` (migration `0007_correction`) → load lại history khỏi gọi LLM

Trả `MessageCorrection` có `diff` (segment keep/remove/add) để render strikethrough/highlight + `nextSuggestions` (3 câu USER có thể nói tiếp, **NOT** lặp lại corrected version — phải là hướng đi mới đẩy hội thoại).

**Voice mode cũng trigger Layer 4** nhưng fire-and-forget (không await, không show UI) — chỉ warm DB cache để sau review history thấy được. Skip nếu `wasRefusal=true` hoặc `userMessageId` rỗng.

System prompt strict JSON output + skip rules (text < 3 từ, `detect_language` mismatch session lang, refusal). Validate parse + fallback `{has_error: false}` an toàn nếu LLM trả format sai.

### 11. Vocabulary dùng SM-2 spaced repetition
- `VocabularyApi.review(id, rating)` gửi `ReviewRating.name` ('again'/'hard'/'good'/'easy') → server tính SM-2, trả vocab state mới. Đừng tính lịch ôn ở client.
- `/vocabulary/due` = từ tới hạn ôn; `/vocabulary/random` = browse khi không có due; `/vocabulary/extract` = AI trích 3-5 từ đáng học từ 1 đoạn text.

### 12. Chấm phát âm — luôn có 2 biến thể path + bytes
`AudioApi` (STT, pronunciation) có cặp method: `...FromFile`/path (mobile/desktop) và `...FromBytes` (web — chỉ có blob/Uint8List, không có file path thật). Khi thêm endpoint audio mới phải làm cả 2. `getPronunciationCoaching` gọi LLM gen hướng dẫn lưỡi/môi/hơi thở cho từ sai.

### 13. Theme & AppColors là static, sync qua ThemeModeNotifier
`AppColors` là palette static có `setDarkMode(bool)`. `ThemeModeNotifier` persist mode qua `TokenStorage.themeMode` VÀ gọi `AppColors.setDarkMode` mỗi lần đổi. Đừng đọc màu trước khi notifier bootstrap, và đừng set màu trực tiếp — luôn qua notifier để 2 nguồn không lệch.

### 14. Tab bar 5 tabs — `MainBottomNav`, KHÔNG back button trên tab screens
5 tab top-level (Home/Sessions/Pronunciation/Vocabulary/Profile) dùng `shared/widgets/main_bottom_nav.dart`. Tap chip → `context.go()` (replace stack, không push).

**Hệ quả**: các màn tab này được vào qua `go()` → stack rỗng → `context.pop()` không có gì để pop. **KHÔNG đặt back button** trên header của tab screens (vd Sessions, Vocabulary, Profile, Pronunciation). ChatScreen + Review + Templates vẫn được `push` lên → có back button đúng cách.

### 15. Language enforcement frontend prepend cho 12 ngôn ngữ
`shared/utils/language_enforcement.dart` chứa `languageEnforcement(langCode)` trả về câu lệnh "respond entirely in {lang}" viết bằng **chính ngôn ngữ đích** (vi/en/ja/ko/zh/fr/es/de/it/pt/ru/th). Khi tạo session, prepend câu này vào `context_prompt`:

- **Home topic chip**: `buildContextPrompt(langCode, rolePlay)` — gộp ép ngôn ngữ + nhập vai
- **Templates flow**: `languageEnforcement(lang)` đơn thuần — bổ sung Layer 1 langdetect retry để model nhỏ (gemma2:2b) không bias sang English với topic English-academic (vd grammar)

Tầng phụ trợ cho Layer 1 backend, không thay thế. Khi gemma2:2b output sai ngôn ngữ → Layer 1 backend re-prompt max 2 retry.

### 16. Template's `system_prompt` có `[language]` placeholder phải substitute trước khi đẩy LLM
Backend `llm_service.build_system_prompt` chạy `_substitute_template_placeholders()` thay `[language]` / `{language}` bằng tên ngôn ngữ thật (vd "English", "Japanese") **trước** khi nối với rules. Lý do: gemma2:2b model nhỏ hay copy nguyên placeholder thay vì hiểu ý → user thấy "Let's learn in [language]" trong output. Map hỗ trợ 13 ngôn ngữ (12 chính + id Indonesian).

### 17. ⚠️ Anti-patterns gây lag/crash Flutter UI — XEM `memory/feedback_flutter_perf.md`
Đã phát hiện 4 anti-pattern khi build voice mode. **Bắt buộc tránh khi build UI có animation/timer**:

1. **`Timer.periodic` + `setState(() {})` rỗng** chỉ để update counter cục bộ → rebuild **toàn screen** mỗi tick. Dùng `ValueNotifier` + `ValueListenableBuilder` bọc duy nhất widget cần update.
2. **`AnimationController..repeat(reverse: true)` từ init** → tick 60fps **suốt lifecycle** dù state idle. Init KHÔNG repeat; thêm helper `_syncAnim()` start/stop dựa state hiện tại.
3. **`Row + List.generate(N, Container)` trong `AnimatedBuilder`** cho waveform/visualization → N widget rebuilds × 60fps = nghìn rebuilds/s. Dùng `CustomPaint + CustomPainter` (1 paint op) + `RepaintBoundary` cô lập layer.
4. **`MaskFilter.blur` / `LinearGradient.createShader` per-frame trong CustomPaint** → CanvasKit web bị `LateInitializationError: Field '_handledContextLostEvent' has not been initialized` (WebGL context lost). Fake glow bằng RRect rộng hơn + alpha thấp, KHÔNG GPU blur.

### 18. Web-only pitfalls đã hardened — đừng remove fallback
- **just_audio web `StreamAudioSource`** experimental không release đúng → dùng `_setBytesSource()` với data URI fallback (`audio_player_service.dart`)
- **record package web MediaStream** không release sau `stop()` → dispose+recreate `AudioRecorder` mỗi `start()` trên web (`voice_recorder.dart`)
- **flutter_secure_storage web `OperationError`** → in-memory fallback (`token_storage.dart`)
- **CanvasKit context loss** từ heavy GPU effects → xem #17 anti-pattern 4

Các fix này áp dụng cả native (Android/iOS) — không cần conditional `kIsWeb`. Nhất quán = ít bug.

## Quy tắc khi sửa code

- **Vietnamese UI strings** — toàn bộ label, message hiển thị cho user là tiếng Việt
- **Màu sắc**: chỉ dùng `AppColors.*` constants. KHÔNG hardcode `Color(0xFF...)` rải rác. Có sẵn 6 `cardGradientN` cho quick-start cards
- **Error UI**: dùng `AppError.message` trực tiếp (đã có message tiếng Việt). Không tự viết lại
- **Provider naming**: `xxxProvider` cho Provider, `xxxStateProvider` cho StateNotifier
- **Refresh provider**: `ref.invalidate(p); await ref.read(p.future);` — KHÔNG dùng `ref.refresh()` (deprecated cho FutureProvider trong Riverpod 2)
- **Không tạo file `.md` documentation** trừ khi user yêu cầu rõ
- **Không add comment giải thích cái gì** — chỉ comment WHY (constraint, workaround, edge case)

## Dart style — TRÁNH các lỗi info/warning của analyzer

Project bật strict lints. Trước khi commit, các pattern sau sẽ tạo info warning. Áp dụng SẴN từ lúc viết code mới để khỏi phải sửa lại:

- **`.withOpacity(X)` → đã deprecated.** Dùng `.withValues(alpha: X)` cho mọi `Color`.
  ```dart
  // ❌ AppColors.error.withOpacity(0.18)
  // ✅ AppColors.error.withValues(alpha: 0.18)
  ```

- **Null-aware map elements** (Dart 3.7+). Khi build `FormData`, `data: {...}`, `Map<...>`:
  ```dart
  // ❌ if (language != null) 'language': language,
  // ✅ 'language': ?language,
  ```
  Tương tự cho List spread điều kiện 1 phần tử nullable: `?action` thay cho `if (action != null) action!`.

- **Unused param chỉ dùng 1 `_`** (không `__`, `___`). Dart 3.7 wildcard cho phép trùng:
  ```dart
  // ❌ builder: (_, __) => Foo(),
  // ✅ builder: (_, _) => Foo(),
  ```

- **Experimental API**: nếu BẮT BUỘC dùng (vd `StreamAudioSource` của just_audio), thêm `// ignore_for_file: experimental_member_use` ở đầu file kèm comment giải thích lý do.

- **Sau khi sửa code Flutter quan trọng → chạy `flutter analyze` để verify 0 issue.** Nếu có file `.dart` thay đổi nhiều, dùng `dart fix --apply` để auto-fix các pattern trên.

## Lệnh thường dùng

```powershell
# Cài deps + chạy
cd flutter_application_1
flutter pub get
flutter run -d chrome      # hoặc -d windows

# Kiểm lỗi tĩnh
flutter analyze

# Hot restart trong terminal đang chạy: bấm R (chữ hoa)
# Thoát mượt: bấm q

# Backend (terminal khác)
cd D:\AI-Assistant-Project\backend_v2
uvicorn app.main:app --reload --port 8000

# Ollama (terminal khác nếu chưa chạy ngầm)
ollama serve
```

## Setup test cho dev nhanh trên máy 16GB RAM
- `.env` backend → `OLLAMA_MODEL=gemma2:2b` (1.6GB, 5-10s/câu trả lời)
- Khi demo chất lượng cao mới đổi sang `gemma2:9b`

## Khi gặp lỗi
1. Mở terminal đang chạy `flutter run` → xem log `[API]` (đã có LogInterceptor trong debug mode)
2. Mở Chrome F12 → tab Network → xem status request thật
3. Mở terminal backend → xem stack trace Python
4. **Đừng đổi code mù** khi chưa biết lỗi backend hay frontend

## Memory (`C:\Users\PC\.claude\projects\d--flutte-Assisant-language\memory\`)
Project có persistent memory cross-session. Index ở `MEMORY.md`. Đọc các file dưới đây khi cần context:
- `user_profile.md` — Mai Thành Đạt, K67-HTTT, ĐH Lâm Nghiệp, GVHD ThS. Mai Hà An
- `project_status.md` — Trạng thái 18 priorities + contract enforcement architecture (4 layers)
- `project_backend.md` — FastAPI endpoints, gemma2:2b, migrations 0001-0007
- `defense_qa.md` — 12 câu hỏi hội đồng + câu trả lời với số liệu
- `chapter4_outline.md` — outline báo cáo Chương 4
- `feedback_flutter_perf.md` — 4 anti-pattern Flutter UI (Timer setState, repeat init, Row+Container in AnimatedBuilder, MaskFilter.blur trên web)
