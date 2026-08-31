import 'package:flutter/foundation.dart';

import 'speech_direction.dart';

/// One completed push-to-talk exchange, after whisper and the translator have
/// both run.
@immutable
class RecognitionTurn {
  const RecognitionTurn({
    required this.direction,
    required this.sourceText,
    required this.translation,
    required this.audioDuration,
    required this.asrTime,
    required this.llmTime,
    required this.createdAt,
    this.audioPath,
  });

  final SpeechDirection direction;

  /// What whisper heard, in the language that was spoken.
  final String sourceText;

  /// The ChatML translator's output, in the target language.
  final String translation;

  final Duration audioDuration;

  /// How long whisper took.
  final Duration asrTime;

  /// How long Qwen took.
  final Duration llmTime;

  final DateTime createdAt;

  /// The WAV in Documents this turn came from.
  final String? audioPath;

  /// The 32pt headline: the translation when present, otherwise the source.
  String get displayText =>
      translation.isNotEmpty ? translation : sourceText;

  bool get hasTranslation => translation.isNotEmpty;
}
