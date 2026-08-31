import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marine_voice_translator/main.dart';
import 'package:marine_voice_translator/models/speech_direction.dart';
import 'package:marine_voice_translator/services/pcm_recorder.dart';
import 'package:marine_voice_translator/services/translation_engine.dart';
import 'package:marine_voice_translator/widgets/push_to_talk_button.dart';

void main() {
  testWidgets('主界面展示两个按住说话的大按键', (tester) async {
    await tester.pumpWidget(const MarineVoiceApp());

    expect(find.text('按住说英文'), findsOneWidget);
    expect(find.text('按住说中文'), findsOneWidget);
    expect(find.text('按住下方按键开始对讲'), findsOneWidget);

    for (final button in tester.widgetList<PushToTalkButton>(
      find.byType(PushToTalkButton),
    )) {
      expect(button.height, greaterThanOrEqualTo(128));
    }
  });

  testWidgets('主界面使用暗黑主题', (tester) async {
    await tester.pumpWidget(const MarineVoiceApp());

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(app.theme?.brightness, Brightness.dark);
  });

  test('PCM 时长按 16 kHz 单声道 16-bit 计算', () {
    expect(PcmFormat.sampleRate, 16000);
    expect(PcmFormat.channels, 1);
    expect(PcmFormat.bytesPerFrame, 2);

    final oneSecond = PcmClip(bytes: Uint8List(PcmFormat.bytesPerSecond));
    expect(oneSecond.duration, const Duration(seconds: 1));
    expect(oneSecond.frameCount, PcmFormat.sampleRate);
  });

  test('WAV 导出写入正确的 RIFF 头', () {
    final clip = PcmClip(bytes: Uint8List(320));
    final wav = clip.toWav();
    final header = ByteData.sublistView(wav);

    expect(wav.length, 44 + 320);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(header.getUint16(22, Endian.little), 1); // 单声道
    expect(header.getUint32(24, Endian.little), 16000); // 采样率
    expect(header.getUint16(34, Endian.little), 16); // 位深
  });

  test('示例引擎按方向返回对应译文', () async {
    final engine = DemoPhrasebookEngine();
    final clip = PcmClip(bytes: Uint8List(PcmFormat.bytesPerSecond));

    final turn = await engine.process(
      clip,
      direction: SpeechDirection.englishToChinese,
    );

    expect(turn.direction, SpeechDirection.englishToChinese);
    expect(turn.recognizedText, isNotEmpty);
    expect(turn.translatedText, isNotEmpty);
    expect(turn.audioDuration, const Duration(seconds: 1));
  });

  test('空音频会被引擎拒绝', () {
    final engine = DemoPhrasebookEngine();

    expect(
      () => engine.process(
        PcmClip(bytes: Uint8List(0)),
        direction: SpeechDirection.chineseToEnglish,
      ),
      throwsA(isA<TranslationException>()),
    );
  });
}
