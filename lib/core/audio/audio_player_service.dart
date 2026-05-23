// StreamAudioSource / StreamAudioResponse là API "experimental" theo just_audio,
// dùng làm fallback cho native. Web giờ dùng data URI nên không cần.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Wrapper quanh just_audio — phát audio từ Uint8List (response của TTS endpoint).
///
/// Hỗ trợ:
/// - 1 player global (chỉ 1 audio play tại 1 thời điểm)
/// - Stream trạng thái (playing/stopped) để UI lắng nghe
/// - Stop khi bắt đầu play audio mới
class AudioPlayerService {
  AudioPlayer _player = AudioPlayer();
  String? _currentMessageId;

  // Stream broadcast cho UI subscribe — KHÔNG đổi qua các lần recreate player.
  // Mỗi khi player mới được tạo, ta forward state stream của nó vào controller này.
  final StreamController<PlayingState> _stateController =
      StreamController<PlayingState>.broadcast();
  StreamSubscription<PlayerState>? _internalStateSub;

  AudioPlayerService() {
    _bindInternalStateStream();
  }

  void _bindInternalStateStream() {
    _internalStateSub?.cancel();
    _internalStateSub = _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        _currentMessageId = null;
        _stateController.add(PlayingState(messageId: null, isPlaying: false));
        return;
      }
      _stateController.add(PlayingState(
        messageId: _currentMessageId,
        isPlaying: s.playing,
      ));
    });
  }

  /// Stream playing state để UI biết audio nào đang play.
  Stream<PlayingState> get stateStream => _stateController.stream;

  String? get currentMessageId => _currentMessageId;

  /// Web bug fix: just_audio + StreamAudioSource (experimental) trên web bị stuck
  /// sau lần play thứ 2 — resource không release đúng. Workaround: dispose +
  /// recreate AudioPlayer mỗi lần play trên web. Trên native không cần.
  Future<void> _ensureFreshPlayerForWeb() async {
    if (!kIsWeb) return;
    try {
      await _internalStateSub?.cancel();
      await _player.dispose();
    } catch (_) {}
    _player = AudioPlayer();
    _bindInternalStateStream();
  }

  Future<void> _setBytesSource(Uint8List audioBytes) async {
    if (kIsWeb) {
      // Data URI — browser HTML5 Audio xử lý native, KHÔNG có bug
      // experimental của StreamAudioSource.
      final dataUri = Uri.dataFromBytes(audioBytes, mimeType: 'audio/mpeg');
      await _player.setAudioSource(AudioSource.uri(dataUri));
    } else {
      await _player.setAudioSource(_BytesSource(audioBytes));
    }
  }

  /// Play audio bytes (MP3) cho 1 message cụ thể. Stops audio đang phát trước đó.
  /// Lưu ý: `_player.play()` chỉ start playback rồi return (KHÔNG block đến hết).
  /// Caller dùng `stateStream` hoặc `playAndAwaitCompletion` để biết khi nào xong.
  Future<void> play({
    required String messageId,
    required Uint8List audioBytes,
  }) async {
    await _ensureFreshPlayerForWeb();
    if (!kIsWeb) {
      await _player.stop();
    }
    _currentMessageId = messageId;
    await _setBytesSource(audioBytes);
    await _player.play();
  }

  /// Play + await đến khi audio thực sự phát xong.
  /// Dùng cho voice conversation mode — đảm bảo mic không mở khi loa còn phát.
  ///
  /// Implementation: track 2-step state machine:
  /// 1) Đợi `playing=true` (đã thực sự bắt đầu phát) → set sawPlaying
  /// 2) Đợi `completed` sau khi sawPlaying → complete
  /// Tránh trigger sớm bởi state cũ trong BehaviorSubject từ turn trước.
  Future<void> playAndAwaitCompletion({
    required String messageId,
    required Uint8List audioBytes,
  }) async {
    await _ensureFreshPlayerForWeb();
    if (!kIsWeb) {
      await _player.stop();
    }
    _currentMessageId = messageId;
    await _setBytesSource(audioBytes);

    final completer = Completer<void>();
    bool sawPlaying = false;
    late StreamSubscription<PlayerState> sub;
    sub = _player.playerStateStream.listen((s) {
      if (s.playing && s.processingState == ProcessingState.ready) {
        sawPlaying = true;
      }
      if (sawPlaying &&
          s.processingState == ProcessingState.completed &&
          !completer.isCompleted) {
        completer.complete();
      }
    });

    await _player.play();

    try {
      // Timeout 30s — audio TTS thông thường < 20s, dư margin
      await completer.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      await _player.stop();
    } finally {
      await sub.cancel();
    }
    _currentMessageId = null;
  }

  Future<void> stop() async {
    _currentMessageId = null;
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _internalStateSub?.cancel();
    await _stateController.close();
    await _player.dispose();
  }
}

class PlayingState {
  final String? messageId;
  final bool isPlaying;
  const PlayingState({required this.messageId, required this.isPlaying});
}

/// AudioSource từ bytes — chỉ dùng cho NATIVE (Windows/Android/iOS).
/// Trên web đã thay bằng data URI vì experimental API này có bug khi replay.
class _BytesSource extends StreamAudioSource {
  final Uint8List _bytes;
  _BytesSource(this._bytes);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_bytes.sublist(start, end)),
      contentType: 'audio/mpeg', // gTTS trả MP3
    );
  }
}
