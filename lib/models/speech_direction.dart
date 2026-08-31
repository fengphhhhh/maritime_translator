import 'package:flutter/material.dart';

import '../theme/night_theme.dart';

/// Which way a single push-to-talk turn is translated.
enum SpeechDirection {
  /// Crew speaks English, the app shows Mandarin.
  englishToChinese,

  /// Crew speaks Mandarin, the app shows English.
  chineseToEnglish;

  String get buttonLabel => switch (this) {
    SpeechDirection.englishToChinese => '按住说英文',
    SpeechDirection.chineseToEnglish => '按住说中文',
  };

  String get routeLabel => switch (this) {
    SpeechDirection.englishToChinese => 'English → 中文',
    SpeechDirection.chineseToEnglish => '中文 → English',
  };

  String get sourceLabel => switch (this) {
    SpeechDirection.englishToChinese => 'English',
    SpeechDirection.chineseToEnglish => '中文',
  };

  String get listeningLabel => switch (this) {
    SpeechDirection.englishToChinese => '正在聆听英文',
    SpeechDirection.chineseToEnglish => '正在聆听中文',
  };

  Color get accent => switch (this) {
    SpeechDirection.englishToChinese => NightPalette.english,
    SpeechDirection.chineseToEnglish => NightPalette.chinese,
  };
}
