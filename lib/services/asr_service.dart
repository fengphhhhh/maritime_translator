import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import '../config/maritime_config.dart';

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
/// inference runs in a background isolate via the `whisper_ggml` FFI plugin.
/// No audio and no text ever leaves the phone.
class AsrService {
  AsrService();

  /// `whisper_ggml` still wants an enum here, but [Whisper.transcribe] loads
  /// whatever `modelPath` points at and never reads this field — the bundled
  /// large-v3-turbo build is not one of the enum's stock names.
  static const WhisperModel _unusedModelSelector = WhisperModel.large;

  String? _modelPath;
  Future<String>? _pendingModelPath;
  bool _isTranscribing = false;
  bool _modelIsParked = false;

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
  Future<void> release() async {
    if (!_modelIsParked) return;
    _modelIsParked = false;

    try {
      await const Whisper(model: _unusedModelSelector).releaseModel();
    } on Object catch (error) {
      debugPrint('AsrService.release: $error');
    }
  }

  // ---------------------------------------------------------------------------
  // Model location
  // ---------------------------------------------------------------------------

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

  /// Finds the ggml model, in order of preference:
  ///
  /// 1. `Documents/models/` — a file dropped in over iTunes/Files sharing,
  ///    which lets a fine-tuned model replace the bundled one without a
  ///    rebuild.
  /// 2. The asset inside the installed `.app` bundle, read in place. A
  ///    turbo-class model is hundreds of megabytes, so avoiding a second copy
  ///    on disk is worth the path arithmetic.
  /// 3. A copy extracted from the Flutter asset bundle into Application
  ///    Support, for when the bundle layout is not what step 2 expects.
  Future<String> _locateModel() async {
    final String fileName = MaritimeConfig.modelFileName;

    final Directory documents = await getApplicationDocumentsDirectory();
    final File override = File('${documents.path}/models/$fileName');
    if (override.existsSync()) return override.path;

    final File inBundle = File(_bundleAssetPath(MaritimeConfig.modelAssetPath));
    if (inBundle.existsSync()) return inBundle.path;

    return _extractFromAssets(fileName);
  }

  /// Path of a Flutter asset inside the installed app bundle.
  ///
  /// On iOS `Platform.resolvedExecutable` is `…/Runner.app/Runner`, and the
  /// asset bundle sits at `Runner.app/Frameworks/App.framework/flutter_assets`.
  String _bundleAssetPath(String assetKey) {
    final String appDirectory = File(Platform.resolvedExecutable).parent.path;
    return '$appDirectory/Frameworks/App.framework/flutter_assets/$assetKey';
  }

  Future<String> _extractFromAssets(String fileName) async {
    final Directory support = await getApplicationSupportDirectory();
    final Directory models = Directory('${support.path}/models');
    await models.create(recursive: true);

    final File destination = File('${models.path}/$fileName');
    if (destination.existsSync() && await destination.length() > 0) {
      return destination.path;
    }

    final ByteData data;
    try {
      data = await rootBundle.load(MaritimeConfig.modelAssetPath);
    } on FlutterError {
      throw AsrException(
        '离线模型 $fileName 未随应用一起打包。\n'
        '请将模型文件放入 assets/models/ 后重新构建，'
        '或通过「文件」App 拷贝到本应用的 Documents/models/ 目录。',
        isModelMissing: true,
      );
    }

    await destination.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    // The asset cache would otherwise hold the whole model in memory.
    rootBundle.evict(MaritimeConfig.modelAssetPath);

    return destination.path;
  }
}
