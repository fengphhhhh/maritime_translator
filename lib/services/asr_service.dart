import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import '../config/maritime_config.dart';
import 'model_locator.dart';
import 'resident_model.dart';

/// Languages the bridge crew speaks, in whisper.cpp's two-letter codes.
enum AsrLanguage {
  english('en'),
  chinese('zh');

  const AsrLanguage(this.code);

  final String code;
}

class AsrException implements Exception {
  const AsrException(this.message, {this.isModelMissing = false});

  final String message;

  /// The model file could not be found; the app needs it installed rather than
  /// a retry.
  final bool isModelMissing;

  @override
  String toString() => 'AsrException: $message';
}

/// Offline speech recognition through whisper.cpp.
///
/// Everything happens on device: the model is read from the app bundle and
/// inference runs in a background isolate via the `whisper_ggml` FFI plugin,
/// on the GPU through ggml's Metal backend. No audio and no text ever leaves
/// the phone.
class AsrService implements ResidentModel {
  AsrService();

  /// `whisper_ggml` still wants an enum here, but [Whisper.transcribe] loads
  /// whatever `modelPath` points at and never reads this field — the bundled
  /// large-v3-turbo build is not one of the enum's stock names.
  static const WhisperModel _unusedModelSelector = WhisperModel.large;

  String? _modelPath;
  Future<String>? _pendingModelPath;
  bool _isTranscribing = false;
  bool _modelIsParked = false;

  @override
  String get residentModelName => '识别';

  @override
  bool get isResident => _modelIsParked;

  /// Absolute path of the model in use, once [prepare] has run.
  String? get modelPath => _modelPath;

  /// Resolves the model file up front so a missing model surfaces on launch
  /// rather than on the user's first press.
  ///
  /// Returns `false` instead of throwing: a missing model is a state the UI
  /// shows, not a crash.
  Future<bool> prepare() async {
    try {
      await _resolveModelPath();
      return true;
    } on AsrException catch (error) {
      debugPrint('AsrService.prepare: ${error.message}');
      return false;
    }
  }

  /// Transcribes the 16 kHz mono WAV at [audioPath].
  ///
  /// Returns the recognised text, trimmed; an empty string means whisper heard
  /// no speech. [onProgress] reports 0–100 while inference runs, which matters
  /// because a turbo-class model takes seconds even on recent hardware.
  Future<String> transcribe(
    String audioPath, {
    AsrLanguage language = AsrLanguage.english,
    void Function(int percent)? onProgress,
  }) async {
    if (_isTranscribing) {
      throw const AsrException('上一段语音仍在识别中，请稍候。');
    }
    if (!File(audioPath).existsSync()) {
      throw AsrException('找不到录音文件：$audioPath');
    }

    // Claimed before the first await so a second press cannot slip past the
    // check above while the model path is being resolved.
    _isTranscribing = true;

    try {
      final String model = await _resolveModelPath();

      final WhisperTranscribeResponse response =
          await const Whisper(model: _unusedModelSelector).transcribe(
            transcribeRequest: TranscribeRequest(
              audio: audioPath,
              language: language.code,
              threads: MaritimeConfig.decoderThreads,
              // Recognition only. Cross-language output is a separate stage.
              isTranslate: false,
              isNoTimestamps: true,
              // The maritime hotwords. Without this, whisper renders the
              // abbreviations phonetically.
              initialPrompt: MaritimeConfig.initialPrompt,
              // Each press is an independent utterance, so no carry-over
              // context: it is the main source of hallucinated repetition on
              // short clips.
              noContext: true,
              // Keeps "[BLANK_AUDIO]" and friends out of the transcript when
              // the user releases the key a beat late.
              suppressNonSpeechTokens: true,
              // Loading a q5_0 turbo model costs seconds; park it in native
              // memory so only the first press pays for it.
              keepModelLoaded: true,
              // Runs the model on the GPU via ggml's Metal backend. Only the
              // forked plugin honours this; the published one is CPU-only.
              useGpu: MaritimeConfig.useMetal,
            ),
            modelPath: model,
            onProgress: onProgress,
          );

      _modelIsParked = true;
      return response.text.trim();
    } on AsrException {
      rethrow;
    } on Object catch (error) {
      throw AsrException('语音识别失败：$error');
    } finally {
      _isTranscribing = false;
      // whisper_ggml pipes every input through ffmpeg into "<path>.wav" before
      // decoding. Ours is already 16 kHz mono, so that copy is pure leftover.
      unawaited(_deleteQuietly('$audioPath.wav'));
    }
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } on Object catch (error) {
      debugPrint('AsrService: 无法删除临时文件 $path: $error');
    }
  }

  /// Frees the model parked in native memory (several GB for the large
  /// models). Call it when recognition is done for a while.
  @override
  Future<void> release() async {
    if (!_modelIsParked) return;
    _modelIsParked = false;

    try {
      await const Whisper(model: _unusedModelSelector).releaseModel();
    } on Object catch (error) {
      debugPrint('AsrService.release: $error');
    }
  }

  Future<String> _resolveModelPath() {
    final String? resolved = _modelPath;
    if (resolved != null) return Future<String>.value(resolved);

    // Concurrent callers share one resolution; extracting the model twice
    // would mean writing hundreds of megabytes twice.
    return _pendingModelPath ??= _locateModel()
        .then((path) {
          _modelPath = path;
          return path;
        })
        .whenComplete(() => _pendingModelPath = null);
  }

  Future<String> _locateModel() async {
    try {
      return await ModelLocator.locate(MaritimeConfig.modelAssetPath);
    } on ModelMissingException catch (error) {
      throw AsrException(
        '离线模型 ${error.fileName} 未随应用一起打包。\n'
        '请将模型文件放入 assets/models/ 后重新构建，'
        '或通过「文件」App 拷贝到本应用的 Documents/models/ 目录。',
        isModelMissing: true,
      );
    }
  }
}
