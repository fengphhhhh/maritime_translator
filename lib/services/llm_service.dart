import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:llama_ggml/llama_ggml.dart';

import '../config/maritime_config.dart';
import 'model_locator.dart';
import 'resident_model.dart';
import 'translation_prompt.dart';

class TranslationException implements Exception {
  const TranslationException(this.message, {this.isModelMissing = false});

  final String message;

  /// The model file could not be found; the app needs it installed rather
  /// than a retry.
  final bool isModelMissing;

  @override
  String toString() => 'TranslationException: $message';
}

/// Offline Chinese/English translation through a small instruct model.
///
/// Runs Qwen2.5-1.5B-Instruct on the iPhone GPU via `llama_ggml`. The model is
/// prompted in ChatML with the maritime glossary inlined, and its output is
/// forced back onto the glossary afterwards — see [TranslationPrompt].
class LlmService implements ResidentModel {
  LlmService();

  LlamaSession? _session;
  String? _modelPath;
  Future<LlamaSession>? _pendingSession;
  bool _isTranslating = false;

  @override
  String get residentModelName => '翻译';

  @override
  bool get isResident => _session != null;

  /// Absolute path of the model in use, once [prepare] has run.
  String? get modelPath => _modelPath;

  /// Resolves the model file up front so a missing model shows on launch
  /// rather than mid-conversation.
  ///
  /// Returns `false` instead of throwing: a missing model is a state the UI
  /// shows, not a crash. Does not load the model — that costs a gigabyte and
  /// waits for the first translation.
  Future<bool> prepare() async {
    try {
      _modelPath ??= await ModelLocator.locate(MaritimeConfig.llmModelAssetPath);
      return true;
    } on ModelMissingException catch (error) {
      debugPrint('LlmService.prepare: 缺少模型 ${error.fileName}');
      return false;
    } on Object catch (error) {
      debugPrint('LlmService.prepare: $error');
      return false;
    }
  }

  /// Translates [text] between Chinese and English.
  ///
  /// [isEnglishToChinese] describes the direction of the whole turn: `true`
  /// means the crew spoke English and wants Chinese back.
  Future<String> translate({
    required String text,
    required bool isEnglishToChinese,
  }) async {
    final String source = text.trim();
    if (source.isEmpty) {
      throw const TranslationException('没有可翻译的内容。');
    }
    if (_isTranslating) {
      throw const TranslationException('上一句仍在翻译中，请稍候。');
    }

    // Claimed before the first await so a second press cannot slip past the
    // check above while the model is loading.
    _isTranslating = true;

    final TranslationTarget target = isEnglishToChinese
        ? TranslationTarget.chinese
        : TranslationTarget.english;

    try {
      final LlamaSession session = await _resolveSession();
      final String raw = await session.generate(
        TranslationPrompt.build(source, target),
        maxTokens: MaritimeConfig.llmMaxTokens,
        // Greedy: the same call on the bridge should read the same way twice.
        temperature: 0,
      );

      final String translated = TranslationPrompt.polish(raw, target);
      if (translated.isEmpty) {
        throw const TranslationException('翻译模型没有输出内容。');
      }
      return translated;
    } on TranslationException {
      rethrow;
    } on ModelMissingException catch (error) {
      throw TranslationException(
        '翻译模型 ${error.fileName} 未随应用一起打包。\n'
        '请将模型文件放入 assets/models/ 后重新构建，'
        '或通过「文件」App 拷贝到本应用的 Documents/models/ 目录。',
        isModelMissing: true,
      );
    } on Object catch (error) {
      throw TranslationException('翻译失败：$error');
    } finally {
      _isTranslating = false;
    }
  }

  @override
  Future<void> release() async {
    final LlamaSession? session = _session;
    _session = null;
    if (session == null) return;

    try {
      await session.release();
    } on Object catch (error) {
      debugPrint('LlmService.release: $error');
    }
  }

  /// Which ggml backends llama.cpp found, e.g. `Metal,CPU`.
  ///
  /// Reports what the process actually registered rather than what the build
  /// flags asked for, which is the only honest way to confirm Metal is live.
  Future<String> describeBackends() async {
    try {
      return await LlamaSession.devices();
    } on Object catch (error) {
      return '未知（$error）';
    }
  }

  Future<LlamaSession> _resolveSession() {
    final LlamaSession? loaded = _session;
    if (loaded != null) return Future<LlamaSession>.value(loaded);

    // Concurrent callers share one load; a second one would mean another
    // gigabyte of weights.
    return _pendingSession ??= _loadSession()
        .then((session) {
          _session = session;
          return session;
        })
        .whenComplete(() => _pendingSession = null);
  }

  Future<LlamaSession> _loadSession() async {
    final String path =
        _modelPath ??= await ModelLocator.locate(MaritimeConfig.llmModelAssetPath);

    if (!File(path).existsSync()) {
      throw TranslationException('找不到翻译模型文件：$path', isModelMissing: true);
    }

    return LlamaSession.load(
      path,
      contextSize: MaritimeConfig.llmContextSize,
      gpuLayers: MaritimeConfig.useMetal ? MaritimeConfig.llmGpuLayers : 0,
      threads: MaritimeConfig.decoderThreads,
    );
  }
}
