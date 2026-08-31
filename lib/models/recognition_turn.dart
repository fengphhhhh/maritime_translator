import 'package:flutter/foundation.dart';

import 'speech_direction.dart';

/// One completed push-to-talk exchange, after whisper has had its say.
@immutable
class RecognitionTurn {
  const RecognitionTurn({
    required this.direction,
    required this.text,
    required this.audioDuration,
    required this.inferenceTime,
    required this.createdAt,
    this.audioPath,
  });

  final SpeechDirection direction;

  /// The transcript, in the language that was spoken. This is the 32pt
  /// headline; the translation stage will sit on top of it later.
  final String text;

  final Duration audioDuration;

  /// How long whisper took. Worth showing: a turbo-class model on CPU is not
  /// instant, and the number tells the user whether the model is warm.
  final Duration inferenceTime;

  final DateTime createdAt;

  /// The WAV in Documents this transcript came from.
  final String? audioPath;
}
