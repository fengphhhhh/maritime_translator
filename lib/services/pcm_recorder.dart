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

  static const String description = '16 kHz · 单声道 · PCM 16-bit';
}

/// A finished push-to-talk capture, held in memory as raw PCM frames.
@immutable
class PcmClip {
  const PcmClip({required this.bytes, this.filePath});

  /// Headerless little-endian PCM frames, ready to hand to an ASR engine.
  final Uint8List bytes;

  /// Where the raw frames were mirrored on disk, or `null` on web.
  final String? filePath;

  int get frameCount => bytes.lengthInBytes ~/ PcmFormat.bytesPerFrame;

  Duration get duration => Duration(
    microseconds:
        bytes.lengthInBytes * Duration.microsecondsPerSecond ~/
        PcmFormat.bytesPerSecond,
  );

  bool get isEmpty => bytes.isEmpty;

  /// Wraps the frames in a 44-byte RIFF header so a clip can be played back or
  /// inspected with any audio tool while debugging the pipeline.
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
/// stay in memory: an offline translator wants the buffer, not a file, and
/// nothing touches the disk unless [mirrorToDisk] asks for it.
class PcmRecorder {
  PcmRecorder({this.mirrorToDisk = true});

  /// Also writes each capture to the documents directory as a `.pcm` file.
  /// Ignored on web, which has no such directory.
  final bool mirrorToDisk;

  static const RecordConfig _config = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: PcmFormat.sampleRate,
    numChannels: PcmFormat.channels,
    bitRate: PcmFormat.bytesPerSecond * 8,
    autoGain: true,
    echoCancel: true,
    noiseSuppress: true,
    androidConfig: AndroidRecordConfig(
      // Engine room and bridge noise: the recognition source applies the
      // platform's speech-tuned front end instead of a flat mic capture.
      audioSource: AndroidAudioSource.voiceRecognition,
    ),
    iosConfig: IosRecordConfig(
      categoryOptions: [
        IosAudioCategoryOption.defaultToSpeaker,
        IosAudioCategoryOption.allowBluetooth,
      ],
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

  /// Stops the capture and returns the frames recorded since [start].
  ///
  /// Returns `null` when no capture was running.
  Future<PcmClip?> stop() async {
    if (!_isRecording) return null;
    _isRecording = false;

    final buffer = _buffer;
    await _finishStream();
    _emit(0);

    final bytes = buffer?.takeBytes() ?? Uint8List(0);
    final path = await _writeToDisk(bytes);

    return PcmClip(bytes: bytes, filePath: path);
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

  Future<String?> _writeToDisk(Uint8List bytes) async {
    if (!mirrorToDisk || kIsWeb || bytes.isEmpty) return null;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final captures = Directory('${directory.path}/captures');
      await captures.create(recursive: true);

      final file = File(
        '${captures.path}/${DateTime.now().millisecondsSinceEpoch}.pcm',
      );
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } on Object catch (error) {
      debugPrint('PcmRecorder: 无法写入录音文件: $error');
      return null;
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
