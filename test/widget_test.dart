import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marine_voice_translator/config/maritime_config.dart';
import 'package:marine_voice_translator/config/maritime_vocabulary.dart';
import 'package:marine_voice_translator/main.dart';
import 'package:marine_voice_translator/models/recognition_turn.dart';
import 'package:marine_voice_translator/models/session_status.dart';
import 'package:marine_voice_translator/models/speech_direction.dart';
import 'package:marine_voice_translator/services/asr_service.dart';
import 'package:marine_voice_translator/services/pcm_recorder.dart';
import 'package:marine_voice_translator/services/translation_prompt.dart';
import 'package:marine_voice_translator/theme/night_theme.dart';
import 'package:marine_voice_translator/widgets/push_to_talk_button.dart';
import 'package:marine_voice_translator/widgets/transcript_stage.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

/// Pumps [TranscriptStage] on its own so each pipeline state can be inspected
/// without a microphone or a whisper model.
Future<void> pumpStage(
  WidgetTester tester, {
  required SessionStatus status,
  RecognitionTurn? turn,
  SpeechDirection? activeDirection,
  int? progress,
  String? sourceText,
  bool showSourceFlash = false,
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
          sourceText: sourceText,
          showSourceFlash: showSourceFlash,
          errorMessage: errorMessage,
          onDismissError: () {},
        ),
      ),
    ),
  );
}

RecognitionTurn buildTurn({
  String source = 'Vessel on my port bow, what are your intentions?',
  String translation = '我船左舷首有船，你船意图如何？',
}) => RecognitionTurn(
  direction: SpeechDirection.englishToChinese,
  sourceText: source,
  translation: translation,
  audioDuration: const Duration(seconds: 3),
  asrTime: const Duration(milliseconds: 1800),
  llmTime: const Duration(milliseconds: 2200),
  createdAt: DateTime(2026),
);

void main() {
  group('主界面', () {
    testWidgets('展示两个按住说话的大按键', (tester) async {
      await tester.pumpWidget(const MarineVoiceApp());

      expect(find.text('按住说英文'), findsOneWidget);
      expect(find.text('按住说中文'), findsOneWidget);
      expect(find.text('按住下方按键开始对讲'), findsOneWidget);
      expect(find.textContaining('离线 · 16 kHz · 单声道'), findsOneWidget);
      expect(find.byIcon(Icons.history_rounded), findsOneWidget);

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

    testWidgets('翻译阶段先闪过原文再显示“正在翻译...”', (tester) async {
      const source = 'Vessel on my port bow';

      await pumpStage(
        tester,
        status: SessionStatus.translating,
        activeDirection: SpeechDirection.englishToChinese,
        sourceText: source,
        showSourceFlash: true,
      );

      expect(find.text(source), findsOneWidget);
      expect(find.text('正在翻译...'), findsNothing);

      await pumpStage(
        tester,
        status: SessionStatus.translating,
        activeDirection: SpeechDirection.englishToChinese,
        sourceText: source,
        showSourceFlash: false,
      );

      expect(find.text('正在翻译...'), findsOneWidget);
    });

    testWidgets('翻译结果以 32pt 呈现', (tester) async {
      const translation = '我船左舷首有船，你船意图如何？';
      await pumpStage(
        tester,
        status: SessionStatus.done,
        turn: buildTurn(translation: translation),
      );

      final result = tester.widget<SelectableText>(
        find.widgetWithText(SelectableText, translation),
      );
      expect(result.style?.fontSize, TranscriptStage.resultFontSize);
      expect(TranscriptStage.resultFontSize, 32);
    });

    testWidgets('原文以更大字号呈现', (tester) async {
      const source = 'Vessel on my port bow, what are your intentions?';
      await pumpStage(
        tester,
        status: SessionStatus.done,
        turn: buildTurn(source: source),
      );

      final sourceText = tester.widget<SelectableText>(
        find.widgetWithText(SelectableText, source),
      );
      expect(sourceText.style?.fontSize, TranscriptStage.sourceFontSize);
      expect(TranscriptStage.sourceFontSize, greaterThanOrEqualTo(20));
    });

    testWidgets('底部显示 ASR 与 LLM 耗时', (tester) async {
      await pumpStage(
        tester,
        status: SessionStatus.done,
        turn: buildTurn(),
      );

      expect(find.textContaining('ASR: 1.8s'), findsOneWidget);
      expect(find.textContaining('LLM: 2.2s'), findsOneWidget);
    });

    testWidgets('空转写结果给出提示而不是空白', (tester) async {
      await pumpStage(
        tester,
        status: SessionStatus.done,
        turn: buildTurn(source: '', translation: ''),
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
          'Third Officer',
          'Dredger',
          'EPIRB',
          'Mayday',
        ]),
      );
      expect(MaritimeConfig.hotwords.length, lessThanOrEqualTo(90));
    });

    test('术语表包含运行时注入条目', () {
      expect(MaritimeConfig.glossary['port bow'], '左舷首');
      expect(MaritimeConfig.glossary['stand by engine'], '主机备车');
      expect(MaritimeVocabulary.vhfCorePhrases.length, 100);
      expect(MaritimeVocabulary.wordGlossary.length, greaterThan(300));
    });

    test('模型文件名由资源路径推导', () {
      expect(MaritimeConfig.modelFileName, 'ggml-large-v3-turbo-q5_0.bin');
      expect(MaritimeConfig.modelAssetPath, startsWith('assets/models/'));
      expect(
        MaritimeConfig.llmModelFileName,
        'qwen2.5-1.5b-instruct-q4_k_m.gguf',
      );
    });
  });

  group('翻译提示词', () {
    test('英译中时术语对照方向正确', () {
      final prompt = TranslationPrompt.build(
        'port bow',
        TranslationTarget.chinese,
      );

      expect(prompt, contains('port bow=左舷首'));
      expect(prompt, contains('starboard=右舷'));
      expect(prompt, isNot(contains('右舷=starboard')));
    });

    test('输出端强制替换术语', () {
      final polished = TranslationPrompt.polish(
        'Port bow clear.',
        TranslationTarget.chinese,
      );

      expect(polished, contains('左舷首'));
      expect(polished.toLowerCase(), isNot(contains('port bow')));
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

  group('Metal 加速', () {
    test('应用默认请求 GPU 推理', () {
      expect(MaritimeConfig.useMetal, isTrue);
    });

    // useGpu only exists on the Metal fork in local_plugins/. Pointing
    // pubspec.yaml back at the published whisper_ggml would silently drop the
    // app to CPU-only inference; instead it stops compiling, here.
    test('依赖的是带 Metal 的插件分支', () {
      const request = TranscribeRequest(audio: '/tmp/clip.wav');

      expect(request.useGpu, isTrue);
      expect(request.copyWith(useGpu: false).useGpu, isFalse);
    });
  });
}
