import 'package:flutter_test/flutter_test.dart';
import 'package:marine_voice_translator/models/recognition_turn.dart';
import 'package:marine_voice_translator/models/speech_direction.dart';
import 'package:marine_voice_translator/models/translation_history_entry.dart';
import 'package:marine_voice_translator/services/translation_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('翻译历史', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('成功翻译后写入并可读取', () async {
      final service = TranslationHistoryService();
      final turn = RecognitionTurn(
        direction: SpeechDirection.englishToChinese,
        sourceText: 'Stand by engine.',
        translation: '主机备车。',
        audioDuration: const Duration(seconds: 2),
        asrTime: const Duration(milliseconds: 900),
        llmTime: const Duration(milliseconds: 1100),
        createdAt: DateTime(2026, 8, 31, 18, 30, 45),
      );

      await service.appendFromTurn(turn);
      final entries = await service.loadAll();

      expect(entries, hasLength(1));
      expect(entries.first.sourceText, 'Stand by engine.');
      expect(entries.first.translationText, '主机备车。');
      expect(entries.first.directionLabel, '英译中');
      expect(entries.first.timestamp, '2026-08-31 18:30:45');
    });

    test('时间戳格式为 yyyy-MM-dd HH:mm:ss', () {
      final formatted = TranslationHistoryEntry.formatTimestamp(
        DateTime(2026, 1, 5, 9, 8, 7),
      );
      expect(formatted, '2026-01-05 09:08:07');
    });

    test('可清空全部历史', () async {
      final service = TranslationHistoryService();
      await service.appendFromTurn(
        RecognitionTurn(
          direction: SpeechDirection.chineseToEnglish,
          sourceText: '左舷有船',
          translation: 'Vessel on port side.',
          audioDuration: Duration.zero,
          asrTime: Duration.zero,
          llmTime: Duration.zero,
          createdAt: DateTime.now(),
        ),
      );

      await service.clearAll();
      expect(await service.loadAll(), isEmpty);
    });
  });
}
