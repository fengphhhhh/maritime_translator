import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// The single audio format the whole app speaks: 16 kHz, mono, signed 16-bit
/// little-endian PCM. On-device ASR engines (whisper.cpp, sherpa-onnx, Vosk)
/// all expect exactly this, so the audio never needs resampling before
/// inference.
abstract final class PcmFormat {
  static const int sampleRate = 16000;
  static const int channels = 1;
  static const int bitsPerSample = 16;
  static const int bytesPerFrame = channels * (bitsPerSample ~/ 8);
  static const int bytesPerSecond = sampleRate * bytesPerFrame;

  static const String description = '16 kHz · 单声道 · 16-bit WAV';
}

/// A finished push-to-talk capture, held in memory as raw PCM frames.
@immutable
class PcmClip {
  const PcmClip({required this.bytes, this.wavPath});

  /// Headerless little-endian PCM frames.
  final Uint8List bytes;

  /// The WAV rendering of [bytes] in the app's Documents directory. This is
  /// the path handed to whisper.cpp, which reads audio from a file.
  final String? wavPath;

  int get frameCount => bytes.lengthInBytes ~/ PcmFormat.bytesPerFrame;

  Duration get duration => Duration(
    microseconds:
        bytes.lengthInBytes * Duration.microsecondsPerSecond ~/
        PcmFormat.bytesPerSecond,
  );

  bool get isEmpty => bytes.isEmpty;

  /// Wraps the frames in a 44-byte RIFF header. Whisper reads a WAV file, and
  /// building the header here guarantees it advertises exactly 16 kHz / mono /
  /// 16-bit rather than whatever an encoder decided to write.
  Uint8List toWav() {
    const headerSize = 44;
    final dataSize = bytes.lengthInBytes;
    final out = Uint8List(headerSize + dataSize);
    final view = ByteData.sublistView(out);

    void writeTag(int offset, String tag) {
      for (var i = 0; i < tag.length; i++) {
        out[offset + i] = tag.codeUnitAt(i);
      }
    }

    writeTag(0, 'RIFF');
    view.setUint32(4, 36 + dataSize, Endian.little);
    writeTag(8, 'WAVE');
    writeTag(12, 'fmt ');
    view.setUint32(16, 16, Endian.little); // PCM chunk size
    view.setUint16(20, 1, Endian.little); // format = PCM
    view.setUint16(22, PcmFormat.channels, Endian.little);
    view.setUint32(24, PcmFormat.sampleRate, Endian.little);
    view.setUint32(28, PcmFormat.bytesPerSecond, Endian.little);
    view.setUint16(32, PcmFormat.bytesPerFrame, Endian.little);
    view.setUint16(34, PcmFormat.bitsPerSample, Endian.little);
    writeTag(36, 'data');
    view.setUint32(40, dataSize, Endian.little);
    out.setRange(headerSize, headerSize + dataSize, bytes);

    return out;
  }
}

class RecorderException implements Exception {
  const RecorderException(this.message, {this.isPermissionDenied = false});

  final String message;
  final bool isPermissionDenied;

  @override
  String toString() => 'RecorderException: $message';
}

/// Push-to-talk wrapper around [AudioRecorder].
///
/// Recording is driven through `startStream` rather than `start` so the frames
/// arrive in memory while the key is held: that is what feeds the live level
/// meter, and it lets this class write the WAV header itself instead of
/// trusting an encoder to produce exactly what whisper.cpp wants.
class PcmRecorder {
  PcmRecorder();

  /// How many finished captures to keep in Documents. They are debugging
  /// material, not user data, and 16 kHz mono runs ~32 KB per second.
  static const int _keepRecentRecordings = 20;

  static const RecordConfig _config = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: PcmFormat.sampleRate,
    numChannels: PcmFormat.channels,
    bitRate: PcmFormat.bytesPerSecond * 8,
    autoGain: true,
    echoCancel: true,
    noiseSuppress: true,
    iosConfig: IosRecordConfig(
      // playAndRecord + defaultToSpeaker so a later playback or alert stage
      // does not have to tear the session down and back up; allowBluetooth
      // picks up a headset on the bridge.
      categoryOptions: [
        IosAudioCategoryOption.defaultToSpeaker,
        IosAudioCategoryOption.allowBluetooth,
        IosAudioCategoryOption.duckOthers,
      ],
      // An incoming call ringing mid-utterance should not kill the capture;
      // only the user actually answering does.
      allowHapticsAndSystemSoundsDuringRecording: true,
    ),
    // ~128 ms per chunk, small enough to drive a responsive level meter.
    streamBufferSize: 4096,
  );

  final AudioRecorder _recorder = AudioRecorder();
  final StreamController<double> _levelController =
      StreamController<double>.broadcast();

  StreamSubscription<Uint8List>? _subscription;
  Completer<void>? _streamClosed;
  BytesBuilder? _buffer;
  bool _isRecording = false;
  bool _isDisposed = false;

  /// Microphone loudness of the most recent chunk, normalised to `0..1`.
  Stream<double> get levelStream => _levelController.stream;

  bool get isRecording => _isRecording;

  /// Checks the microphone permission without showing a system prompt.
  Future<bool> hasPermission() => _recorder.hasPermission(request: false);

  /// Prompts for the microphone permission if it has not been granted yet.
  Future<bool> requestPermission() => _recorder.hasPermission();

  /// Applies the app's `AVAudioSession` category before the first capture.
  ///
  /// `record` activates the session itself; this only pins the category and
  /// options so the choice lives in the app rather than in the plugin's
  /// defaults.
  Future<void> configureAudioSession() async {
    final RecordIos? ios = _recorder.ios;
    if (ios == null) return;

    try {
      await ios.manageAudioSession(true);
      await ios.setAudioSessionCategory(
        category: IosAudioCategory.playAndRecord,
        options: const [
          IosAudioCategoryOptions.defaultToSpeaker,
          IosAudioCategoryOptions.allowBluetooth,
          IosAudioCategoryOptions.duckOthers,
        ],
      );
    } on Object catch (error) {
      debugPrint('PcmRecorder: 音频会话配置失败: $error');
    }
  }

  Future<void> start() async {
    if (_isRecording) return;

    if (!await _recorder.hasPermission()) {
      throw const RecorderException(
        '麦克风权限未开启，请在系统设置中允许本应用使用麦克风。',
        isPermissionDenied: true,
      );
    }

    final buffer = BytesBuilder(copy: false);
    final closed = Completer<void>();

    late final Stream<Uint8List> stream;
    try {
      stream = await _recorder.startStream(_config);
    } on Exception catch (error) {
      throw RecorderException('无法启动录音：$error');
    }

    _buffer = buffer;
    _streamClosed = closed;
    _isRecording = true;

    _subscription = stream.listen(
      (chunk) {
        buffer.add(chunk);
        _emitLevel(chunk);
      },
      onError: (Object error) {
        _emit(0);
        if (!closed.isCompleted) closed.completeError(error);
      },
      onDone: () {
        _emit(0);
        if (!closed.isCompleted) closed.complete();
      },
      cancelOnError: true,
    );
  }

  /// Stops the capture, writes it to Documents as a WAV, and returns it.
  ///
  /// Returns `null` when no capture was running.
  Future<PcmClip?> stop() async {
    if (!_isRecording) return null;
    _isRecording = false;

    final buffer = _buffer;
    await _finishStream();
    _emit(0);

    final bytes = buffer?.takeBytes() ?? Uint8List(0);
    final clip = PcmClip(bytes: bytes);

    return PcmClip(bytes: bytes, wavPath: await _writeWav(clip));
  }

  /// Stops the capture and throws the frames away (press cancelled, app
  /// backgrounded, permission revoked mid-turn).
  Future<void> cancel() async {
    if (!_isRecording) return;
    _isRecording = false;

    await _finishStream();
    _buffer = null;
    _emit(0);
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    _isRecording = false;
    await _subscription?.cancel();
    _subscription = null;
    _buffer = null;
    await _recorder.dispose();
    await _levelController.close();
  }

  Future<void> _finishStream() async {
    // `record` flushes the tail of the capture as the stream closes, so wait
    // for the done event instead of cancelling the subscription immediately.
    try {
      await _recorder.stop();
      await _streamClosed?.future.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // Fall through: whatever arrived is what we have.
    } on Object catch (error, stackTrace) {
      debugPrintStack(
        label: 'PcmRecorder.stop failed: $error',
        stackTrace: stackTrace,
      );
    } finally {
      _streamClosed = null;
      await _subscription?.cancel();
      _subscription = null;
    }
  }

  /// Writes [clip] to `Documents/recordings/` as a 16 kHz mono WAV and returns
  /// its path, which is what the ASR stage consumes.
  Future<String?> _writeWav(PcmClip clip) async {
    if (clip.isEmpty) return null;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final recordings = Directory('${directory.path}/recordings');
      await recordings.create(recursive: true);

      final file = File(
        '${recordings.path}/${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      await file.writeAsBytes(clip.toWav(), flush: true);

      unawaited(_pruneRecordings(recordings));
      return file.path;
    } on Object catch (error) {
      debugPrint('PcmRecorder: 无法写入录音文件: $error');
      return null;
    }
  }

  Future<void> _pruneRecordings(Directory recordings) async {
    try {
      final files = recordings
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.wav'))
          .toList();
      if (files.length <= _keepRecentRecordings) return;

      files.sort((a, b) => b.path.compareTo(a.path));
      for (final file in files.skip(_keepRecentRecordings)) {
        await file.delete();
      }
    } on Object catch (error) {
      debugPrint('PcmRecorder: 清理历史录音失败: $error');
    }
  }

  void _emitLevel(Uint8List chunk) {
    if (chunk.lengthInBytes < PcmFormat.bytesPerFrame) return;

    // `chunk` may start at an odd byte offset, so read through a ByteData view
    // rather than reinterpreting the buffer as Int16List.
    final view = ByteData.sublistView(chunk);
    var sumOfSquares = 0.0;
    var count = 0;
    for (var i = 0; i + 1 < chunk.lengthInBytes; i += 2) {
      final sample = view.getInt16(i, Endian.little) / 32768.0;
      sumOfSquares += sample * sample;
      count++;
    }
    if (count == 0) return;

    final rms = math.sqrt(sumOfSquares / count);
    if (rms <= 0) {
      _emit(0);
      return;
    }

    // Map -55 dBFS (bridge background noise) .. 0 dBFS onto the meter.
    const floorDb = -55.0;
    final db = 20 * math.log(rms) / math.ln10;
    _emit(((db - floorDb) / -floorDb).clamp(0.0, 1.0));
  }

  void _emit(double level) {
    if (_levelController.isClosed) return;
    _levelController.add(level);
  }
}
