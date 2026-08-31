import 'package:flutter/foundation.dart';

import 'speech_direction.dart';

/// One saved translation exchange for the on-device history log.
@immutable
class TranslationHistoryEntry {
  const TranslationHistoryEntry({
    required this.id,
    required this.sourceText,
    required this.translationText,
    required this.direction,
    required this.timestamp,
  });

  final String id;
  final String sourceText;
  final String translationText;
  final SpeechDirection direction;

  /// Formatted as `yyyy-MM-dd HH:mm:ss`.
  final String timestamp;

  String get directionLabel => direction.resultLabel;

  Map<String, Object> toJson() => {
    'id': id,
    'sourceText': sourceText,
    'translationText': translationText,
    'direction': direction.name,
    'timestamp': timestamp,
  };

  factory TranslationHistoryEntry.fromJson(Map<String, dynamic> json) {
    return TranslationHistoryEntry(
      id: json['id'] as String,
      sourceText: json['sourceText'] as String,
      translationText: json['translationText'] as String,
      direction: SpeechDirection.values.byName(json['direction'] as String),
      timestamp: json['timestamp'] as String,
    );
  }

  static String formatTimestamp(DateTime time) {
    final y = time.year.toString().padLeft(4, '0');
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final h = time.hour.toString().padLeft(2, '0');
    final min = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min:$s';
  }
}
