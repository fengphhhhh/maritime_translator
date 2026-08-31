import 'package:flutter/material.dart';

import '../services/asr_service.dart';
import '../theme/night_theme.dart';

/// Which language the crew speaks into a push-to-talk key.
///
/// The names describe the eventual translation direction; for now only the
/// spoken side is used, to tell whisper which language to decode.
enum SpeechDirection {
  /// Crew speaks English.
  englishToChinese,

  /// Crew speaks Mandarin.
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

  /// Pill above the transcript.
  String get resultLabel => switch (this) {
    SpeechDirection.englishToChinese => '英文识别结果',
    SpeechDirection.chineseToEnglish => '中文识别结果',
  };

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
