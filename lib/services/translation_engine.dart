import 'dart:math';

import '../data/smcp_phrasebook.dart';
import '../models/speech_direction.dart';
import '../models/translation_turn.dart';
import 'pcm_recorder.dart';

/// Turns a captured PCM clip into a transcript plus its translation.
///
/// Everything runs on device: no implementation of this interface may reach the
/// network, because the app is expected to work with the antennas down.
abstract interface class TranslationEngine {
  String get displayName;

  Future<TranslationTurn> process(
    PcmClip clip, {
    required SpeechDirection direction,
  });
}

class TranslationException implements Exception {
  const TranslationException(this.message);

  final String message;

  @override
  String toString() => 'TranslationException: $message';
}

/// Placeholder engine that keeps the UI honest until the real models land.
///
/// It does not look at the audio content — it walks the bundled SMCP phrasebook
/// and waits roughly as long as an on-device pass would take. Swap this for a
/// real pipeline (sherpa-onnx or whisper.cpp for ASR, then a quantised NMT
/// model for the translation step) by implementing [TranslationEngine] and
/// handing the new instance to the home page.
class DemoPhrasebookEngine implements TranslationEngine {
  DemoPhrasebookEngine({Random? random}) : _random = random ?? Random();

  final Random _random;
  final Map<SpeechDirection, int> _cursor = {};

  @override
  String get displayName => '离线示例引擎';

  @override
  Future<TranslationTurn> process(
    PcmClip clip, {
    required SpeechDirection direction,
  }) async {
    if (clip.isEmpty) {
      throw const TranslationException('没有采集到音频，请检查麦克风后重试。');
    }

    // Stand-in for inference time: roughly a third of the clip length.
    final thinkingMs = (clip.duration.inMilliseconds ~/ 3).clamp(350, 1400);
    await Future<void>.delayed(Duration(milliseconds: thinkingMs));

    final phrases = phrasesFor(direction);
    final index = _cursor.update(
      direction,
      (value) => (value + 1) % phrases.length,
      ifAbsent: () => _random.nextInt(phrases.length),
    );
    final phrase = phrases[index];

    return TranslationTurn(
      direction: direction,
      recognizedText: phrase.source(direction),
      translatedText: phrase.target(direction),
      audioDuration: clip.duration,
      createdAt: DateTime.now(),
    );
  }
}
