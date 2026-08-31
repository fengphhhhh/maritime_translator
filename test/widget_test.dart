import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marine_voice_translator/config/maritime_config.dart';
import 'package:marine_voice_translator/main.dart';
import 'package:marine_voice_translator/models/recognition_turn.dart';
import 'package:marine_voice_translator/models/session_status.dart';
import 'package:marine_voice_translator/models/speech_direction.dart';
import 'package:marine_voice_translator/services/asr_service.dart';
import 'package:marine_voice_translator/services/pcm_recorder.dart';
import 'package:marine_voice_translator/theme/night_theme.dart';
import 'package:marine_voice_translator/widgets/push_to_talk_button.dart';
import 'package:marine_voice_translator/widgets/transcript_stage.dart';

/// Pumps [TranscriptStage] on its own so each pipeline state can be inspected
/// without a microphone or a whisper model.
Future<void> pumpStage(
  WidgetTester tester, {
  required SessionStatus status,
  RecognitionTurn? turn,
  SpeechDirection? activeDirection,
  int? progress,
  String? errorMessage,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: NightTheme.build(),
      home: Scaffold(
        body: TranscriptStage(
          status: status,
          turn: turn,
          activeDirection: activeDirection,
          elapsed: const Duration(seconds: 2),
          level: 0.5,
          progress: progress,
          errorMessage: errorMessage,
          onDismissError: () {},
        ),
      ),
    ),
  );
}

RecognitionTurn buildTurn(String text) => RecognitionTurn(
  direction: SpeechDirection.englishToChinese,
  text: text,
  audioDuration: const Duration(seconds: 3),
  inferenceTime: const Duration(milliseconds: 1800),
  createdAt: DateTime(2026),
);

void main() {
  group('主界面', () {
    testWidgets('展示两个按住说话的大按键', (tester) async {
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

    testWidgets('使用暗黑主题', (tester) async {
      await tester.pumpWidget(const MarineVoiceApp());

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);
      expect(app.theme?.brightness, Brightness.dark);
    });
  });

  group('识别状态', () {
    testWidgets('松开按键后显示“正在识别中...”', (tester) async {
      await pumpStage(
        tester,
        status: SessionStatus.recognizing,
        activeDirection: SpeechDirection.englishToChinese,
      );

      expect(find.text('正在识别中...'), findsOneWidget);
    });

    testWidgets('有进度时显示百分比', (tester) async {
      await pumpStage(
        tester,
        status: SessionStatus.recognizing,
        activeDirection: SpeechDirection.chineseToEnglish,
        progress: 42,
      );

      expect(find.text('42'), findsOneWidget);

      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(indicator.value, closeTo(0.42, 0.001));
    });

    testWidgets('识别结果以 32pt 呈现', (tester) async {
      const transcript = 'Vessel on my port bow, what are your intentions?';
      await pumpStage(
        tester,
        status: SessionStatus.done,
        turn: buildTurn(transcript),
      );

      final result = tester.widget<SelectableText>(
        find.widgetWithText(SelectableText, transcript),
      );
      expect(result.style?.fontSize, TranscriptStage.resultFontSize);
      expect(TranscriptStage.resultFontSize, 32);
    });

    testWidgets('空转写结果给出提示而不是空白', (tester) async {
      await pumpStage(
        tester,
        status: SessionStatus.done,
        turn: buildTurn(''),
      );

      expect(find.text('没有识别到语音内容'), findsOneWidget);
    });

    testWidgets('失败时展示错误信息', (tester) async {
      await pumpStage(
        tester,
        status: SessionStatus.failed,
        errorMessage: '离线模型未随应用一起打包。',
      );

      expect(find.text('离线模型未随应用一起打包。'), findsOneWidget);
      expect(find.text('知道了'), findsOneWidget);
    });
  });

  group('航海热词配置', () {
    test('initial_prompt 包含全部热词', () {
      final prompt = MaritimeConfig.initialPrompt;

      for (final word in MaritimeConfig.hotwords) {
        expect(prompt, contains(word));
      }
      expect(prompt, startsWith(MaritimeConfig.promptPreamble));
    });

    test('热词表覆盖约定的航海缩写', () {
      expect(
        MaritimeConfig.hotwords,
        containsAll(<String>[
          'VTS',
          'CPA',
          'TCPA',
          'UKC',
          'ECDIS',
          'AIO',
          'Port Bow',
          'Starboard',
          'Underway',
          'Draught',
          'Anchor',
          'Pilot',
          'Gangway',
          'Fairway',
          'Master',
          'Chief Officer',
          'Second Mate',
          'Dredger',
        ]),
      );
    });

    test('模型文件名由资源路径推导', () {
      expect(MaritimeConfig.modelFileName, 'ggml-large-v3-turbo-q5_0.bin');
      expect(MaritimeConfig.modelAssetPath, startsWith('assets/models/'));
    });
  });

  group('音频格式', () {
    test('固定为 16 kHz 单声道 16-bit', () {
      expect(PcmFormat.sampleRate, 16000);
      expect(PcmFormat.channels, 1);
      expect(PcmFormat.bytesPerFrame, 2);

      final oneSecond = PcmClip(bytes: Uint8List(PcmFormat.bytesPerSecond));
      expect(oneSecond.duration, const Duration(seconds: 1));
      expect(oneSecond.frameCount, PcmFormat.sampleRate);
    });

    test('WAV 头声明 Whisper 需要的格式', () {
      final clip = PcmClip(bytes: Uint8List(320));
      final wav = clip.toWav();
      final header = ByteData.sublistView(wav);

      expect(wav.length, 44 + 320);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(header.getUint16(20, Endian.little), 1); // PCM
      expect(header.getUint16(22, Endian.little), 1); // 单声道
      expect(header.getUint32(24, Endian.little), 16000); // 采样率
      expect(header.getUint16(34, Endian.little), 16); // 位深
    });
  });

  group('按键与识别语言', () {
    test('英文键解码英文，中文键解码中文', () {
      expect(
        SpeechDirection.englishToChinese.asrLanguage,
        AsrLanguage.english,
      );
      expect(
        SpeechDirection.chineseToEnglish.asrLanguage,
        AsrLanguage.chinese,
      );
      expect(AsrLanguage.english.code, 'en');
      expect(AsrLanguage.chinese.code, 'zh');
    });
  });
}
