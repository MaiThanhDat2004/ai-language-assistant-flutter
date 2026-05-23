import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Wrapper quanh `record` package — quản lý lifecycle ghi âm.
///
/// Tách riêng để chat_screen.dart không phụ thuộc trực tiếp vào `record`,
/// dễ test và dễ thay impl sau này (vd dùng platform channel riêng).
class VoiceRecorder {
  // Non-final: trên web ta dispose + recreate mỗi lần start để release
  // MediaStream (mic track) hoàn toàn — package `record` KHÔNG tự stop
  // các MediaStreamTracks sau khi MediaRecorder dừng, khiến lần record
  // thứ 2 lấy stream stale hoặc bị block.
  AudioRecorder _recorder = AudioRecorder();
  String? _currentPath;
  DateTime? _startedAt;

  Future<bool> hasPermission() async {
    // Trên web, package record có check riêng (getUserMedia)
    if (kIsWeb) {
      return _recorder.hasPermission();
    }
    // Trên mobile/desktop dùng permission_handler để xin quyền tường minh
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  bool get isRecording => _startedAt != null;

  /// Thời gian đã ghi (giây). Dùng để hiển thị duration trên UI.
  Duration get elapsed => _startedAt == null
      ? Duration.zero
      : DateTime.now().difference(_startedAt!);

  /// Stream amplitude (0.0-1.0 typically, có thể âm nếu dB) — dùng cho VAD
  /// (Voice Activity Detection) trong voice conversation mode.
  /// Emit mỗi `interval` (mặc định 100ms).
  Stream<Amplitude> amplitudeStream({
    Duration interval = const Duration(milliseconds: 100),
  }) {
    return _recorder.onAmplitudeChanged(interval);
  }

  Future<void> start() async {
    if (isRecording) return;
    final ok = await hasPermission();
    if (!ok) throw const VoiceRecorderException('Cần quyền microphone');

    // Web fix: dispose + recreate AudioRecorder để đảm bảo MediaStream cũ
    // (mic track) được release hoàn toàn trước khi getUserMedia lại. Không
    // làm bước này → turn 2+ trong voice conversation mode bị stuck.
    if (kIsWeb) {
      try {
        await _recorder.dispose();
      } catch (_) {}
      _recorder = AudioRecorder();
    }

    // Output format: WAV 16kHz mono — Whisper preferred format, nhỏ + nhanh
    const config = RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      numChannels: 1,
    );

    if (kIsWeb) {
      // Web không có file path — record vào memory stream
      await _recorder.start(config, path: '');
    } else {
      final dir = await getTemporaryDirectory();
      _currentPath =
          '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _recorder.start(config, path: _currentPath!);
    }
    _startedAt = DateTime.now();
  }

  /// Stop và trả về kết quả ghi âm.
  /// - Trên mobile: trả filePath
  /// - Trên web: trả bytes
  Future<RecordResult?> stop() async {
    if (!isRecording) return null;
    final pathOrUrl = await _recorder.stop();
    _startedAt = null;

    if (pathOrUrl == null) return null;

    if (kIsWeb) {
      // Web: pathOrUrl là blob URL → fetch ra bytes
      final bytes = await _fetchBlobBytes(pathOrUrl);
      return RecordResult(
        filename: 'recording.wav',
        bytes: bytes,
      );
    }
    return RecordResult(
      filename: 'recording.wav',
      filePath: pathOrUrl,
    );
  }

  /// Huỷ bỏ ghi âm (không lưu kết quả).
  Future<void> cancel() async {
    if (!isRecording) return;
    await _recorder.stop();
    _startedAt = null;
    _currentPath = null;
  }

  Future<void> dispose() async {
    await _recorder.dispose();
  }

  /// Web only: fetch bytes từ blob URL trả về bởi package record.
  ///
  /// Trên web, `recorder.stop()` trả về URL dạng `blob:http://localhost:XXXX/abc`.
  /// Đây là pointer đến Blob trong memory của browser, KHÔNG phải file thật.
  /// Dùng Dio (XHR trên web) để fetch lại bytes từ blob URL này.
  Future<Uint8List> _fetchBlobBytes(String blobUrl) async {
    // Dio instance riêng — không dùng apiClient vì nó có baseUrl tới backend,
    // sẽ làm hỏng URL nếu blobUrl là absolute path khác.
    final dio = Dio();
    final response = await dio.get<List<int>>(
      blobUrl,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data ?? []);
  }
}

class RecordResult {
  final String filename;
  final String? filePath; // mobile/desktop
  final Uint8List? bytes; // web

  const RecordResult({required this.filename, this.filePath, this.bytes});

  bool get isWeb => bytes != null;
}

class VoiceRecorderException implements Exception {
  final String message;
  const VoiceRecorderException(this.message);
  @override
  String toString() => 'VoiceRecorderException: $message';
}
