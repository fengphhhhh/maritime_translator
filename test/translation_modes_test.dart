import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marine_voice_translator/main.dart';
import 'package:marine_voice_translator/models/recognition_turn.dart';
import 'package:marine_voice_translator/models/session_status.dart';
import 'package:marine_voice_translator/models/speech_direction.dart';
import 'package:marine_voice_translator/models/translation_mode.dart';
import 'package:marine_voice_translator/models/translation_history_entry.dart';
import 'package:marine_voice_translator/services/asr_service.dart';
import 'package:marine_voice_translator/services/doubao_s2t_service.dart';
import 'package:marine_voice_translator/services/llm_service.dart';
import 'package:marine_voice_translator/services/pcm_recorder.dart';
import 'package:marine_voice_translator/services/translation_history_service.dart';
import 'package:marine_voice_translator/services/translation_settings.dart';
import 'package:marine_voice_translator/theme/night_theme.dart';
import 'package:marine_voice_translator/widgets/push_to_talk_button.dart';
import 'package:marine_voice_translator/widgets/transcript_stage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeKeys extends ApiKeyStore {
  FakeKeys([this.value = 'test-key']);
  String? value;
  String? arkValue = 'test-ark-key';
  @override
  Future<String?> readArk() async => arkValue;
  @override
  Future<void> saveArk(String key) async {
    arkValue = key;
  }

  @override
  Future<void> deleteArk() async {
    arkValue = null;
  }

  @override
  Future<String?> read() async => value;
  @override
  Future<void> save(String key) async {
    value = key;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

class FakeSettings extends TranslationSettings {
  FakeSettings(this.mode);
  TranslationMode mode;
  @override
  Future<TranslationMode> loadMode() async => mode;
  @override
  Future<void> saveMode(TranslationMode value) async {
    mode = value;
  }

  @override
  Future<OnlineVocabulary> loadVocabulary() async => const OnlineVocabulary();
}

class FakeAsr extends AsrService {
  int calls = 0;
  @override
  Future<bool> prepare() async => false;
  @override
  Future<String> transcribe(
    String audioPath, {
    AsrLanguage language = AsrLanguage.english,
    void Function(int)? onProgress,
  }) async {
    calls++;
    return 'I require a pilot.';
  }

  @override
  Future<void> release() async {}
}

class FakeLlm extends LlmService {
  int calls = 0;
  @override
  Future<bool> prepare() async => false;
  @override
  Future<String> translate({
    required String text,
    required bool isEnglishToChinese,
  }) async {
    calls++;
    return '我船需要引航员。';
  }

  @override
  Future<void> release() async {}
}

class FakeRecorder extends PcmRecorder {
  int starts = 0;
  @override
  Stream<double> get levelStream => const Stream.empty();
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<void> configureAudioSession() async {}
  @override
  Future<void> start() async {
    starts++;
  }

  @override
  Future<PcmClip?> stop() async => PcmClip(
    bytes: Uint8List.fromList(List.generate(32000, (i) => i % 255)),
    wavPath: 'test-recording.wav',
  );
  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async {}
}

class FakeOnline extends DoubaoS2tService {
  int calls = 0, cancels = 0;
  String? hotword, glossary;
  Completer<OnlineTranslation>? pending;
  bool fail = false;
  @override
  Future<OnlineTranslation> translate({
    required Uint8List wav,
    required String apiKey,
    required bool englishSource,
    String hotwordTableId = '',
    String glossaryTableId = '',
    void Function(OnlineTranslation)? onUpdate,
  }) async {
    calls++;
    hotword = hotwordTableId;
    glossary = glossaryTableId;
    onUpdate?.call(const OnlineTranslation('I require a pilot.', '我船需要'));
    if (fail) throw const OnlineTranslationException('在线网络失败，请手动切换离线。');
    return pending?.future ??
        Future.value(const OnlineTranslation('I require a pilot.', '我船需要引航员。'));
  }

  @override
  void cancel() {
    cancels++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpHome(
    WidgetTester tester, {
    required FakeSettings settings,
    required FakeKeys keys,
    required FakeAsr asr,
    required FakeLlm llm,
    required FakeOnline online,
    required FakeRecorder recorder,
  }) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: NightTheme.build(),
        home: TranslatorHomePage(
          settings: settings,
          keyStore: keys,
          asrService: asr,
          llmService: llm,
          onlineService: online,
          recorder: recorder,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> speak(
    WidgetTester tester, {
    bool checkNotSentWhileHeld = false,
    FakeOnline? online,
  }) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PushToTalkButton).first),
    );
    await tester.pump(const Duration(milliseconds: 500));
    if (checkNotSentWhileHeld) expect(online!.calls, 0);
    await gesture.up();
    await tester.pump();
  }

  test(
    'AST and Ark credentials use separate native entries and never preferences',
    () async {
      final secrets = <String, String>{};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ApiKeyStore.channel, (call) async {
            final account = call.method.endsWith('Ark') ? 'ark' : 'ast';
            if (call.method.startsWith('save')) {
              secrets[account] = call.arguments as String;
            }
            if (call.method.startsWith('delete')) secrets.remove(account);
            return call.method.startsWith('read') ? secrets[account] : null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ApiKeyStore.channel, null),
      );
      final store = ApiKeyStore();
      await store.save('private-ast');
      await store.saveArk('private-ark');
      expect(await store.read(), 'private-ast');
      expect(await store.readArk(), 'private-ark');
      await store.deleteArk();
      expect(await store.readArk(), isNull);
      expect(await store.read(), 'private-ast');
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      await expectLater(store.saveArk('bad\nkey'), throwsFormatException);
    },
  );

  testWidgets(
    'missing Ark key opens settings before recording with saved AST key',
    (tester) async {
      final keys = FakeKeys()..arkValue = null;
      final recorder = FakeRecorder(), online = FakeOnline();
      await pumpHome(
        tester,
        settings: FakeSettings(TranslationMode.online),
        keys: keys,
        asr: FakeAsr(),
        llm: FakeLlm(),
        online: online,
        recorder: recorder,
      );
      await speak(tester);
      await tester.pumpAndSettle();
      expect(find.text('豆包在线设置'), findsOneWidget);
      expect(recorder.starts, 0);
      expect(online.calls, 0);
    },
  );

  test(
    'corrected history retains raw recognition and old data remains readable',
    () async {
      final history = TranslationHistoryService();
      await history.appendFromTurn(
        RecognitionTurn(
          direction: SpeechDirection.englishToChinese,
          sourceText: 'I require a pilot.',
          translation: '我船需要引航员。',
          originalTranscript: 'I require a pirate.',
          audioDuration: Duration.zero,
          asrTime: Duration.zero,
          llmTime: Duration.zero,
          createdAt: DateTime(2026),
          mode: TranslationMode.online,
        ),
      );
      final entry = (await history.loadAll()).single;
      expect(entry.sourceText, 'I require a pilot.');
      expect(entry.originalTranscript, 'I require a pirate.');
      expect(
        TranslationHistoryEntry.fromJson(entry.toJson()).originalTranscript,
        entry.originalTranscript,
      );
    },
  );

  test(
    'mode and vocabulary persist, while API key uses only the native channel',
    () async {
      final calls = <MethodCall>[];
      var secret = '';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ApiKeyStore.channel, (call) async {
            calls.add(call);
            if (call.method == 'save') secret = call.arguments as String;
            if (call.method == 'delete') secret = '';
            return call.method == 'read' ? secret : null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ApiKeyStore.channel, null),
      );
      final settings = TranslationSettings(), store = ApiKeyStore();
      expect(await settings.loadMode(), TranslationMode.offline);
      await settings.saveMode(TranslationMode.online);
      await store.save('private-test-value');
      await settings.saveVocabulary(
        const OnlineVocabulary(
          hotwordTableId: '',
          glossaryTableId: 'user-table',
        ),
      );
      expect(await settings.loadMode(), TranslationMode.online);
      expect((await settings.loadVocabulary()).hotwordTableId, '');
      expect(await store.read(), 'private-test-value');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().any(
          (k) => '${prefs.get(k)}'.contains('private-test-value'),
        ),
        isFalse,
      );
      await store.delete();
      expect(await store.read(), '');
      expect(
        calls.map((c) => c.method),
        containsAll(['save', 'read', 'delete']),
      );
      await expectLater(store.save('bad\r\nkey'), throwsFormatException);
    },
  );

  testWidgets(
    'online release calls S2T with both user tables and no local inference',
    (tester) async {
      final asr = FakeAsr(), llm = FakeLlm(), online = FakeOnline();
      await pumpHome(
        tester,
        settings: FakeSettings(TranslationMode.online),
        keys: FakeKeys(),
        asr: asr,
        llm: llm,
        online: online,
        recorder: FakeRecorder(),
      );
      expect(find.textContaining('录音发送至豆包'), findsOneWidget);
      expect(find.text('ASR 缺失'), findsNothing);
      await speak(tester, checkNotSentWhileHeld: true, online: online);
      await tester.pumpAndSettle();
      expect(online.calls, 1);
      expect(asr.calls, 0);
      expect(llm.calls, 0);
      expect(online.hotword, OnlineVocabulary.defaultHotwordId);
      expect(online.glossary, OnlineVocabulary.defaultGlossaryId);
      final history = await TranslationHistoryService().loadAll();
      expect(history.single.mode, TranslationMode.online);
      expect(history.single.translationText, '我船需要引航员。');
      expect(find.textContaining('AST + 方舟 · 在线'), findsOneWidget);
    },
  );

  testWidgets('offline processing never calls the online service', (
    tester,
  ) async {
    final asr = FakeAsr(), llm = FakeLlm(), online = FakeOnline();
    await pumpHome(
      tester,
      settings: FakeSettings(TranslationMode.offline),
      keys: FakeKeys(),
      asr: asr,
      llm: llm,
      online: online,
      recorder: FakeRecorder(),
    );
    await speak(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(asr.calls, 1);
    expect(llm.calls, 1);
    expect(online.calls, 0);
  });

  testWidgets('online failure does not retry or silently fall back offline', (
    tester,
  ) async {
    final asr = FakeAsr(), llm = FakeLlm(), online = FakeOnline()..fail = true;
    await pumpHome(
      tester,
      settings: FakeSettings(TranslationMode.online),
      keys: FakeKeys(),
      asr: asr,
      llm: llm,
      online: online,
      recorder: FakeRecorder(),
    );
    await speak(tester);
    await tester.pumpAndSettle();
    expect(online.calls, 1);
    expect(asr.calls, 0);
    expect(llm.calls, 0);
    expect(find.textContaining('在线网络失败'), findsOneWidget);
    expect(await TranslationHistoryService().loadAll(), isEmpty);
  });

  testWidgets('missing API key opens settings before any recording or upload', (
    tester,
  ) async {
    final recorder = FakeRecorder(), online = FakeOnline();
    await pumpHome(
      tester,
      settings: FakeSettings(TranslationMode.online),
      keys: FakeKeys(null),
      asr: FakeAsr(),
      llm: FakeLlm(),
      online: online,
      recorder: recorder,
    );
    await speak(tester);
    await tester.pumpAndSettle();
    expect(find.text('豆包在线设置'), findsOneWidget);
    expect(recorder.starts, 0);
    expect(online.calls, 0);
    expect(find.text(OnlineVocabulary.defaultHotwordId), findsOneWidget);
    expect(find.text(OnlineVocabulary.defaultGlossaryId), findsOneWidget);
  });

  testWidgets('backgrounding discards a late online result', (tester) async {
    final online = FakeOnline()..pending = Completer<OnlineTranslation>();
    await pumpHome(
      tester,
      settings: FakeSettings(TranslationMode.online),
      keys: FakeKeys(),
      asr: FakeAsr(),
      llm: FakeLlm(),
      online: online,
      recorder: FakeRecorder(),
    );
    await speak(tester);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    online.pending!.complete(const OnlineTranslation('Late result.', '迟到的译文。'));
    await tester.pumpAndSettle();
    expect(online.cancels, greaterThan(0));
    expect(find.text('迟到的译文。'), findsNothing);
    expect(await TranslationHistoryService().loadAll(), isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets(
    'settings keep an existing key hidden and save replacement plus table IDs',
    (tester) async {
      final keys = FakeKeys('old-hidden-test-value');
      await pumpHome(
        tester,
        settings: FakeSettings(TranslationMode.online),
        keys: keys,
        asr: FakeAsr(),
        llm: FakeLlm(),
        online: FakeOnline(),
        recorder: FakeRecorder(),
      );
      await tester.tap(find.byTooltip('在线设置'));
      await tester.pumpAndSettle();
      expect(find.text('old-hidden-test-value'), findsNothing);
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'new-local-test-value');
      await tester.enterText(fields.at(1), 'new-ark-test-value');
      await tester.enterText(fields.at(2), 'ep-seed21-test');
      await tester.ensureVisible(fields.at(3));
      await tester.enterText(fields.at(3), 'custom-hotword');
      await tester.ensureVisible(fields.at(4));
      await tester.enterText(fields.at(4), 'custom-glossary');
      await tester.ensureVisible(find.text('保存设置'));
      await tester.tap(find.text('保存设置'));
      await tester.pumpAndSettle();
      expect(keys.value, 'new-local-test-value');
      expect(keys.arkValue, 'new-ark-test-value');
      expect(await TranslationSettings().loadArkModel(), 'ep-seed21-test');
      final vocabulary = await TranslationSettings().loadVocabulary();
      expect(vocabulary.hotwordTableId, 'custom-hotword');
      expect(vocabulary.glossaryTableId, 'custom-glossary');
      expect(find.text('豆包在线设置'), findsNothing);
    },
  );

  testWidgets('deleting the local key updates online readiness', (
    tester,
  ) async {
    final keys = FakeKeys();
    await pumpHome(
      tester,
      settings: FakeSettings(TranslationMode.online),
      keys: keys,
      asr: FakeAsr(),
      llm: FakeLlm(),
      online: FakeOnline(),
      recorder: FakeRecorder(),
    );
    await tester.tap(find.byTooltip('在线设置'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('删除本机密钥'));
    await tester.tap(find.text('删除本机密钥'));
    await tester.pumpAndSettle();
    expect(keys.value, isNull);
    expect(find.text('待设置密钥'), findsOneWidget);
  });

  testWidgets('mode selector remembers an explicit online choice', (
    tester,
  ) async {
    final settings = FakeSettings(TranslationMode.offline);
    await pumpHome(
      tester,
      settings: settings,
      keys: FakeKeys(),
      asr: FakeAsr(),
      llm: FakeLlm(),
      online: FakeOnline(),
      recorder: FakeRecorder(),
    );
    await tester.tap(find.text('在线'));
    await tester.pumpAndSettle();
    expect(settings.mode, TranslationMode.online);
    expect(find.text('密钥已保存'), findsOneWidget);
  });

  testWidgets('long bilingual results scroll without overflowing the screen', (
    tester,
  ) async {
    final source = 'Please report your present position. ' * 100;
    final translation = '请报告你船当前船位。' * 100;
    await tester.pumpWidget(
      MaterialApp(
        theme: NightTheme.build(),
        home: Scaffold(
          body: SizedBox(
            height: 420,
            width: 400,
            child: TranscriptStage(
              status: SessionStatus.done,
              turn: RecognitionTurn(
                direction: SpeechDirection.englishToChinese,
                sourceText: source,
                translation: translation,
                audioDuration: Duration.zero,
                asrTime: Duration.zero,
                llmTime: Duration.zero,
                createdAt: DateTime(2026),
                mode: TranslationMode.online,
              ),
              activeDirection: null,
              elapsed: Duration.zero,
              level: 0,
              progress: null,
              sourceText: null,
              showSourceFlash: false,
              errorMessage: null,
              onDismissError: () {},
              mode: TranslationMode.online,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(source), findsOneWidget);
    expect(find.text(translation), findsOneWidget);
  });

  test('old saved histories remain offline and round-trip the mode field', () {
    final entry = TranslationHistoryEntry.fromJson({
      'id': 'old',
      'sourceText': 'Hello',
      'translationText': '你好',
      'direction': 'englishToChinese',
      'timestamp': '2026-11-05 12:00:00',
    });
    expect(entry.mode, TranslationMode.offline);
    expect(entry.toJson()['mode'], 'offline');
  });
}
