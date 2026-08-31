import 'package:flutter/material.dart';

import '../services/asr_service.dart';
import '../theme/night_theme.dart';

/// Which language the crew speaks into a push-to-talk key.
enum SpeechDirection {
  /// Crew speaks English; translation is Chinese.
  englishToChinese,

  /// Crew speaks Mandarin; translation is English.
  chineseToEnglish;

  String get buttonLabel => switch (this) {
    SpeechDirection.englishToChinese => '按住说英文',
    SpeechDirection.chineseToEnglish => '按住说中文',
  };

  /// Small line under the key label.
  String get buttonSubtitle => switch (this) {
    SpeechDirection.englishToChinese => 'English',
    SpeechDirection.chineseToEnglish => '普通话',
  };

  String get listeningLabel => switch (this) {
    SpeechDirection.englishToChinese => '正在聆听英文',
    SpeechDirection.chineseToEnglish => '正在聆听中文',
  };

  /// Pill above the translation.
  String get resultLabel => switch (this) {
    SpeechDirection.englishToChinese => '英译中',
    SpeechDirection.chineseToEnglish => '中译英',
  };

  /// Whether the crew spoke English on this key.
  bool get isEnglishToChinese => this == SpeechDirection.englishToChinese;

  /// The language whisper decodes for this key.
  AsrLanguage get asrLanguage => switch (this) {
    SpeechDirection.englishToChinese => AsrLanguage.english,
    SpeechDirection.chineseToEnglish => AsrLanguage.chinese,
  };

  Color get accent => switch (this) {
    SpeechDirection.englishToChinese => NightPalette.english,
    SpeechDirection.chineseToEnglish => NightPalette.chinese,
  };
}
