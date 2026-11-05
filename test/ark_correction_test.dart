import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marine_voice_translator/services/ark_correction_service.dart';
import 'package:marine_voice_translator/services/doubao_s2t_service.dart';
import 'package:marine_voice_translator/services/maritime_online_service.dart';
import 'package:marine_voice_translator/services/translation_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Widget binding replaces HTTP with a synthetic 400 client. These integration
// tests intentionally use real loopback sockets and never a provider account.
class LoopbackHttpOverrides extends HttpOverrides {}

class ChatServer {
  ChatServer(this.server);
  final HttpServer server;
  final received = Completer<void>();
  final release = Completer<void>();
  final requests = <Map<String, dynamic>>[];
  final headers = <String?>[];
  int status = 200;
  String source = 'I require a pilot.';
  String translation = '我船需要引航员。';
  String finish = 'stop';
  String? content;
  bool hold = false;

  static Future<ChatServer> open() async {
    final fixture = ChatServer(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    fixture.server.listen(fixture.handle);
    return fixture;
  }

  Future<void> handle(HttpRequest request) async {
    try {
      headers.add(request.headers.value('Authorization'));
      requests.add(
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>,
      );
      if (!received.isCompleted) received.complete();
      if (hold) await release.future;
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        status == 200
            ? jsonEncode({
                'choices': [
                  {
                    'finish_reason': finish,
                    'message': {
                      'content':
                          content ??
                          jsonEncode({
                            'source': source,
                            'translation': translation,
                          }),
                      'reasoning_content': 'must not be displayed or stored',
                    },
                  },
                ],
              })
            : 'SENTINEL_ARK_KEY provider echo',
      );
      await request.response.close();
    } on Object {
      /* A cancelled test client may already have disconnected. */
    }
  }

  ArkCorrectionService service({
    Duration timeout = const Duration(seconds: 3),
  }) => ArkCorrectionService(
    endpoint: Uri.parse('http://127.0.0.1:${server.port}/chat/completions'),
    timeout: timeout,
  );
  Future<void> close() async {
    if (!release.isCompleted) release.complete();
    await server.close(force: true);
  }
}

class PipelineKeys extends ApiKeyStore {
  String? ark = 'SENTINEL_ARK_KEY';
  Completer<String?>? waiting;
  @override
  Future<String?> readArk() async => waiting == null ? ark : waiting!.future;
}

class PipelineAst extends DoubaoS2tService {
  int calls = 0, cancels = 0;
  Completer<OnlineTranslation>? pending;
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
    expect(apiKey, 'SENTINEL_AST_KEY');
    expect(hotwordTableId, OnlineVocabulary.defaultHotwordId);
    onUpdate?.call(
      const OnlineTranslation('I require a pirate.', '错误 AST 临时译文'),
    );
    return pending?.future ??
        const OnlineTranslation('I require a pirate.', '错误 AST 最终译文');
  }

  @override
  void cancel() {
    cancels++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = LoopbackHttpOverrides();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<OnlineTranslation> correct(
    ChatServer server, {
    String text = 'I require a pirate.',
    bool english = true,
  }) => server.service().correct(
    transcript: text,
    englishSource: english,
    apiKey: 'SENTINEL_ARK_KEY',
    model: TranslationSettings.defaultArkModel,
  );

  test('real HTTP Chat request disables thinking and sends text only with maritime prompt', () async {
    final server = await ChatServer.open();
    addTearDown(server.close);
    final result = await correct(server);
    final body = server.requests.single;
    expect(server.headers.single, 'Bearer SENTINEL_ARK_KEY');
    expect(body['model'], TranslationSettings.defaultArkModel);
    expect(body['thinking'], {'type': 'disabled'});
    expect(body.containsKey('reasoning_effort'), isFalse);
    expect(body['stream'], false);
    expect(body['response_format'], {'type': 'json_object'});
    final messages = body['messages'] as List;
    expect(messages.length, 2);
    expect(messages[0]['role'], 'system');
    expect(messages[0]['content'], contains('SMCP'));
    expect(messages[0]['content'], contains('ICAO'));
    expect(jsonDecode(messages[1]['content'] as String), {
      'source_language': 'en',
      'target_language': 'zh',
      'text': 'I require a pirate.',
    });
    expect(jsonEncode(body), isNot(contains('SENTINEL_AST_KEY')));
    expect(result.source, 'I require a pilot.');
    expect(result.translation, '我船需要引航员。');
    expect(result.transcript, 'I require a pirate.');
  });

  test('Chinese input retains reverse translation', () async {
    final server = await ChatServer.open();
    addTearDown(server.close);
    server.source = '我船需要引航员。';
    server.translation = 'I require a pilot.';
    final result = await correct(server, text: server.source, english: false);
    expect(result.translation, 'I require a pilot.');
    expect(
      jsonDecode(
        (server.requests.single['messages'] as List)[1]['content'] as String,
      )['target_language'],
      'en',
    );
  });

  for (final status in [400, 401, 403, 404, 429, 500]) {
    test(
      'HTTP $status gives a bounded error without provider echo or retries',
      () async {
        final server = await ChatServer.open();
        addTearDown(server.close);
        server.status = status;
        await expectLater(
          correct(server),
          throwsA(
            isA<OnlineTranslationException>().having(
              (e) => e.message,
              'message',
              allOf(contains('$status'), isNot(contains('SENTINEL_ARK_KEY'))),
            ),
          ),
        );
        expect(server.requests.length, 1);
      },
    );
  }

  for (final malformed in [
    'plain answer',
    '{"source":"Hi"}',
    '{"source":"Hi","translation":"你好","explanation":"extra"}',
    '{"source":"","translation":"你好"}',
  ]) {
    test(
      'rejects malformed or incomplete bilingual payload $malformed',
      () async {
        final server = await ChatServer.open();
        addTearDown(server.close);
        server.content = malformed;
        await expectLater(
          correct(server),
          throwsA(isA<OnlineTranslationException>()),
        );
      },
    );
  }

  test('truncated output is never a final translation', () async {
    final server = await ChatServer.open();
    addTearDown(server.close);
    server.finish = 'length';
    await expectLater(
      correct(server),
      throwsA(isA<OnlineTranslationException>()),
    );
  });

  for (final pair in [
    [
      'Course one zero seven degrees.',
      'Course one seven zero degrees.',
      '航向170度。',
    ],
    [
      'Port engines half astern.',
      'Starboard engines half astern.',
      '右舷主机半速后退。',
    ],
    ['Do not enter.', 'Enter.', '进入。'],
    ['Enter.', 'Do not enter.', '不要进入。'],
    ['Port engines half astern.', 'Port engines half ahead.', '左舷主机半速前进。'],
    ['Call sign Alpha Bravo.', 'Call sign Alpha Charlie.', '呼号AC。'],
    ['Call sign AB12.', 'Call sign AC12.', '呼号AC12。'],
  ]) {
    test('rejects changed protected information: ${pair.first}', () async {
      final server = await ChatServer.open();
      addTearDown(server.close);
      server.source = pair[1];
      server.translation = pair[2];
      await expectLater(
        correct(server, text: pair[0]),
        throwsA(isA<OnlineTranslationException>()),
      );
    });
  }

  for (final wording in [
    ['我们左对左过。', '我们右舷对右舷通过。', 'We will pass starboard to starboard.'],
    ['我们右对右过。', '我们左舷对左舷通过。', 'We will pass port to port.'],
    ['我们左对左过。', '我们左舷对左舷通过。', 'We will pass starboard to starboard.'],
    ['我们右对右过。', '我们右舷对右舷通过。', 'We will pass port to port.'],
  ]) {
    test(
      'opposite passing side is still rejected: ${wording[0]} ${wording[2]}',
      () async {
        final server = await ChatServer.open();
        addTearDown(server.close);
        server.source = wording[1];
        server.translation = wording[2];
        await expectLater(
          correct(server, text: wording[0], english: false),
          throwsA(isA<OnlineTranslationException>()),
        );
      },
    );
  }

  test('equivalent radio digits and ICAO spelling normalize without changing values', () async {
    final server = await ChatServer.open();
    addTearDown(server.close);
    server.source = 'AB, course 107 degrees.';
    server.translation = 'AB，航向107度。';
    final result = await correct(
      server,
      text: 'Alpha Bravo, course one zero seven degrees.',
    );
    expect(result.source, server.source);
  });

  test('translation numeric mismatch is rejected after correction', () async {
    final server = await ChatServer.open();
    addTearDown(server.close);
    server.source = 'Course 107 degrees.';
    server.translation = '航向170度。';
    await expectLater(
      correct(server, text: server.source),
      throwsA(isA<OnlineTranslationException>()),
    );
  });

  test('standard short rudder order remains valid in both languages', () async {
    final server = await ChatServer.open();
    addTearDown(server.close);
    server.source = 'Port ten.';
    server.translation = '左舵10度。';
    final result = await correct(server, text: 'Port ten.');
    expect(result.translation, '左舵10度。');
  });

  for (final wording in [
    ['我们左对左过。', '我们左舷对左舷通过。', 'We will pass port to port.'],
    ['我们右对右过。', '我们右舷对右舷通过。', 'We will pass starboard to starboard.'],
    ['我们左对左过。', '我们左对左过。', 'We will pass port-to-port.'],
    ['我们左对左过。', '我们左舷对左舷通过。', 'Port-to-port passing.'],
    ['我们右对右过。', '我们右对右过。', 'We will pass starboard-to-starboard.'],
  ]) {
    test(
      'colloquial passing agreement produces a final translation: ${wording[0]} ${wording[1]}',
      () async {
        final server = await ChatServer.open();
        addTearDown(server.close);
        server.source = wording[1];
        server.translation = wording[2];
        final result = await correct(server, text: wording[0], english: false);
        expect(result.source, wording[1]);
        expect(result.translation, wording[2]);
        expect(result.transcript, wording[0]);
      },
    );
  }

  test('timeout closes transport and reports no final result', () async {
    final server = await ChatServer.open();
    addTearDown(server.close);
    server.hold = true;
    final service = server.service(timeout: const Duration(milliseconds: 100));
    await expectLater(
      service.correct(
        transcript: 'I require a pilot.',
        englishSource: true,
        apiKey: 'key',
        model: TranslationSettings.defaultArkModel,
      ),
      throwsA(
        isA<OnlineTranslationException>().having(
          (e) => e.message,
          'message',
          contains('超时'),
        ),
      ),
    );
  });

  test('pipeline waits for AST, hides AST translation, and sends transcript to Ark', () async {
    final server = await ChatServer.open();
    addTearDown(server.close);
    final ast = PipelineAst()..pending = Completer<OnlineTranslation>();
    final service = MaritimeOnlineService(
      keyStore: PipelineKeys(),
      settings: TranslationSettings(),
      ast: ast,
      ark: server.service(),
    );
    final partials = <OnlineTranslation>[];
    final pending = service.translate(
      wav: Uint8List(1),
      apiKey: 'SENTINEL_AST_KEY',
      englishSource: true,
      hotwordTableId: OnlineVocabulary.defaultHotwordId,
      onUpdate: partials.add,
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(server.requests, isEmpty);
    ast.pending!.complete(
      const OnlineTranslation('I require a pirate.', '不要采用的 AST 译文'),
    );
    final result = await pending;
    expect(result.translation, '我船需要引航员。');
    expect(partials.every((p) => p.translation.isEmpty), isTrue);
    expect(result.transcript, 'I require a pirate.');
    expect(ast.calls, 1);
    expect(server.requests.length, 1);
  });

  test('missing Ark credential stops before any audio upload', () async {
    final ast = PipelineAst();
    final service = MaritimeOnlineService(
      keyStore: PipelineKeys()..ark = null,
      settings: TranslationSettings(),
      ast: ast,
    );
    await expectLater(
      service.translate(wav: Uint8List(1), apiKey: 'key', englishSource: true),
      throwsA(isA<OnlineTranslationException>()),
    );
    expect(ast.calls, 0);
  });

  test(
    'cancel during AST prevents a late transcript from starting Ark',
    () async {
      final server = await ChatServer.open();
      addTearDown(server.close);
      final ast = PipelineAst()..pending = Completer<OnlineTranslation>();
      final service = MaritimeOnlineService(
        keyStore: PipelineKeys(),
        settings: TranslationSettings(),
        ast: ast,
        ark: server.service(),
      );
      final pending = service.translate(
        wav: Uint8List(1),
        apiKey: 'SENTINEL_AST_KEY',
        englishSource: true,
        hotwordTableId: OnlineVocabulary.defaultHotwordId,
      );
      final assertion = expectLater(
        pending,
        throwsA(isA<OnlineTranslationException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      service.cancel();
      ast.pending!.complete(
        const OnlineTranslation('I require a pilot.', '错误译文'),
      );
      await assertion;
      expect(server.requests, isEmpty);
      expect(ast.cancels, 1);
    },
  );

  test(
    'cancel during Ark closes request and permits a new translation',
    () async {
      final server = await ChatServer.open();
      addTearDown(server.close);
      server.hold = true;
      final service = server.service();
      final first = service.correct(
        transcript: 'I require a pilot.',
        englishSource: true,
        apiKey: 'key',
        model: TranslationSettings.defaultArkModel,
      );
      final assertion = expectLater(
        first,
        throwsA(isA<OnlineTranslationException>()),
      );
      await server.received.future;
      service.cancel();
      await assertion;
      server.hold = false;
      final second = await service.correct(
        transcript: 'I require a pilot.',
        englishSource: true,
        apiKey: 'key',
        model: TranslationSettings.defaultArkModel,
      );
      expect(second.translation, '我船需要引航员。');
    },
  );
}
