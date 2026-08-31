import 'package:flutter/foundation.dart';

import 'speech_direction.dart';

/// One completed push-to-talk exchange: what was heard, and what it became.
@immutable
class TranslationTurn {
  const TranslationTurn({
    required this.direction,
    required this.recognizedText,
    required this.translatedText,
    required this.audioDuration,
    required this.createdAt,
  });

  final SpeechDirection direction;

  /// Transcript in the language that was spoken.
  final String recognizedText;

  /// Transcript rendered in the other language; this is the 32pt headline.
  final String translatedText;

  final Duration audioDuration;
  final DateTime createdAt;
}
