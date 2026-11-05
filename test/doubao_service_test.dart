import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marine_voice_translator/services/doubao_protocol.dart';
import 'package:marine_voice_translator/services/doubao_s2t_service.dart';
import 'package:marine_voice_translator/services/pcm_recorder.dart';
import 'package:marine_voice_translator/services/translation_settings.dart';

Uint8List unhex(String text) => Uint8List.fromList([
  for (var i = 0; i < text.length; i += 2)
    int.parse(text.substring(i, i + 2), radix: 16),
]);

Uint8List reply(
  int event,
  String session, [
  String text = '',
  int status = 20000000,
]) {
  final meta = ProtoWriter()
    ..string(1, session)
    ..integer(3, status)
    ..string(4, 'server detail must not be echoed: SENTINEL_KEY');
  return (ProtoWriter()
        ..bytes(1, meta.build())
        ..integer(2, event)
        ..string(4, text))
      .build();
}

class LocalAst {
  LocalAst(this.server, this.behavior);
  final HttpServer server;
  String behavior;
  final sockets = <WebSocket>[];
  final requests = <Map<int, Object>>[];
  final audio = BytesBuilder();
  final started = Completer<void>();
  final peerClosed = Completer<void>();
  Map<String, String> headers = {};
  bool accepted = false, prematureAudio = false;

  static Future<LocalAst> open(String behavior) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final ast = LocalAst(server, behavior);
    server.listen(ast.handle);
    return ast;
  }

  Future<void> handle(HttpRequest request) async {
    headers = {
      'key': request.headers.value('X-Api-Key') ?? '',
      'resource': request.headers.value('X-Api-Resource-Id') ?? '',
    };
    final socket = await WebSocketTransformer.upgrade(request);
    sockets.add(socket);
    var session = '';
    socket.listen(
      (dynamic data) {
        final fields = ProtoReader(Uint8List.fromList(data as List<int>))
            .fields();
        requests.add(fields);
        final meta = ProtoReader(fields[1]! as Uint8List).fields();
        session = utf8.decode(meta[6]! as Uint8List);
        switch (fields[2]) {
          case 100:
            if (behavior == 'timeout') return;
            if (behavior == 'rejected') {
              socket.add(reply(153, session, '', 45000001));
              return;
            }
            if (behavior == 'malformed') {
              socket.add([0]);
              return;
            }
            Timer(const Duration(milliseconds: 10), () {
              accepted = true;
              socket.add(reply(150, session));
              if (!started.isCompleted) started.complete();
              if (behavior == 'disconnect') unawaited(socket.close());
            });
          case 200:
            prematureAudio |= !accepted;
            final block = ProtoReader(fields[4]! as Uint8List).fields();
            audio.add(block[14]! as Uint8List);
          case 102:
            if (behavior == 'wait') return;
            final source = behavior == 'reverse'
                ? '我船需要引航员。'
                : behavior == 'number'
                ? 'Course one-zero-seven degrees.'
                : 'Port engines half astern.';
            final target = behavior == 'reverse'
                ? 'I require a pilot.'
                : behavior == 'number'
                ? '航向170度。'
                : '左舷主机半速后退。';
            socket.add(reply(650, session));
            socket.add(reply(651, session, source.substring(0, 3)));
            socket.add(reply(652, session, source));
            socket.add(reply(653, session));
            socket.add(reply(654, session, target.substring(0, 3)));
            if (behavior != 'unfinished') {
              socket.add(reply(655, session, target));
            }
            if (behavior == 'multi') {
              socket.add(reply(650, session));
              socket.add(reply(652, session, 'Keep clear of me.'));
              socket.add(reply(653, session));
              socket.add(reply(654, session, '请避让'));
              socket.add(reply(655, session, '请避让我船。'));
            }
            socket.add(reply(152, session));
        }
      },
      onError: (Object _) {},
      onDone: () {
        if (!peerClosed.isCompleted) {
          peerClosed.complete();
        }
      },
    );
  }

  DoubaoS2tService service({
    Duration timeout = const Duration(seconds: 2),
    bool transcriptOnly = false,
  }) => DoubaoS2tService(
    transcriptOnly: transcriptOnly,
    responseTimeout: timeout,
    packetInterval: Duration.zero,
    connector: (headers) =>
        WebSocket.connect('ws://127.0.0.1:${server.port}', headers: headers),
  );
  Future<void> close() async {
    for (final socket in sockets) {
      await socket.close();
    }
    await server.close(force: true);
  }
}

void main() {
  final wav = PcmClip(bytes: Uint8List(6400)).toWav();
  final fixture = jsonDecode(
    File('test/fixtures/doubao_ast_v2_golden.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  test('chained mode accepts completed transcript despite inaccurate AST translation', () async {
    final ast = await LocalAst.open('number');
    addTearDown(ast.close);
    final result = await ast
        .service(transcriptOnly: true)
        .translate(wav: wav, apiKey: 'key', englishSource: true);
    expect(result.source, 'Course one-zero-seven degrees.');
  });

  test(
    'chained mode requires only a final source and session finish',
    () async {
      final ast = await LocalAst.open('unfinished');
      addTearDown(ast.close);
      final result = await ast
          .service(transcriptOnly: true)
          .translate(wav: wav, apiKey: 'key', englishSource: true);
      expect(result.source, 'Port engines half astern.');
    },
  );

  test(
    'Dart requests exactly match independently generated official protobuf',
    () {
      final requests = fixture['requests'] as Map<String, dynamic>;
      for (final english in [true, false]) {
        expect(
          DoubaoProtocol.start(
            'fixture-session',
            englishSource: english,
            boostingTableId: OnlineVocabulary.defaultHotwordId,
            glossaryTableId: OnlineVocabulary.defaultGlossaryId,
          ),
          unhex(requests[english ? 'start_en' : 'start_zh'] as String),
        );
      }
      expect(
        DoubaoProtocol.audio(
          'fixture-session',
          Uint8List.fromList([82, 73, 70, 70, 0, 1, 255]),
        ),
        unhex(requests['audio'] as String),
      );
      expect(
        DoubaoProtocol.finish('fixture-session'),
        unhex(requests['finish'] as String),
      );
    },
  );

  test(
    'official server response fixtures decode including errors and UTF-8',
    () {
      for (final dynamic row in fixture['responses']) {
        final decoded = DoubaoResponse.decode(unhex(row['hex'] as String));
        expect(decoded.event, row['event']);
        expect(decoded.text, row['text']);
        expect(decoded.status, row['status']);
        expect(decoded.sessionId, 'fixture-session');
        expect(decoded.startTime, 120);
        expect(decoded.endTime, 980);
      }
      expect(() => DoubaoResponse.decode([10, 9, 1]), throwsFormatException);
    },
  );

  test('real local websocket waits for acceptance and sends exact WAV with table IDs', () async {
    final ast = await LocalAst.open('multi');
    addTearDown(ast.close);
    final partials = <OnlineTranslation>[];
    final result = await ast.service().translate(
      wav: wav,
      apiKey: 'SENTINEL_KEY',
      englishSource: true,
      hotwordTableId: OnlineVocabulary.defaultHotwordId,
      glossaryTableId: OnlineVocabulary.defaultGlossaryId,
      onUpdate: partials.add,
    );
    expect(ast.prematureAudio, isFalse);
    expect(ast.audio.toBytes(), wav);
    expect(ast.headers['key'], 'SENTINEL_KEY');
    expect(ast.headers['resource'], DoubaoProtocol.resourceId);
    final start = ast.requests.first;
    expect(start.containsKey(5), isFalse); // No audio/TTS output configuration.
    final params = ProtoReader(start[6]! as Uint8List).fields();
    expect(utf8.decode(params[1]! as Uint8List), 's2t');
    expect(utf8.decode(params[2]! as Uint8List), 'en');
    final corpus = ProtoReader(params[100]! as Uint8List).fields();
    expect(
      utf8.decode(corpus[2]! as Uint8List),
      OnlineVocabulary.defaultHotwordId,
    );
    expect(
      utf8.decode(corpus[14]! as Uint8List),
      OnlineVocabulary.defaultGlossaryId,
    );
    expect(corpus.containsKey(9), isFalse);
    expect(corpus.containsKey(10), isFalse);
    expect(result.source, 'Port engines half astern. Keep clear of me.');
    expect(result.translation, '左舷主机半速后退。请避让我船。');
    expect(partials, isNotEmpty);
  });

  test(
    'Chinese-to-English uses reversed language settings without local models',
    () async {
      final ast = await LocalAst.open('reverse');
      addTearDown(ast.close);
      final result = await ast.service().translate(
        wav: wav,
        apiKey: 'test',
        englishSource: false,
      );
      final params = ProtoReader(ast.requests.first[6]! as Uint8List).fields();
      expect(utf8.decode(params[2]! as Uint8List), 'zh');
      expect(utf8.decode(params[3]! as Uint8List), 'en');
      expect(result.translation, 'I require a pilot.');
      final corpus = ProtoReader(params[100]! as Uint8List).fields();
      expect(corpus.containsKey(9), isTrue);
      expect(corpus.containsKey(10), isTrue);
    },
  );

  for (final behavior in [
    'rejected',
    'malformed',
    'disconnect',
    'unfinished',
    'number',
    'timeout',
  ]) {
    test(
      'handles $behavior without returning partial success or leaking secrets',
      () async {
        final ast = await LocalAst.open(behavior);
        addTearDown(ast.close);
        try {
          await ast
              .service(
                timeout: behavior == 'timeout'
                    ? const Duration(milliseconds: 100)
                    : const Duration(seconds: 3),
              )
              .translate(wav: wav, apiKey: 'SENTINEL_KEY', englishSource: true);
          fail('A failed session was accepted');
        } on OnlineTranslationException catch (error) {
          expect(error.message, isNot(contains('SENTINEL_KEY')));
          if (behavior == 'number') expect(error.message, contains('数字'));
          if (behavior == 'unfinished') expect(error.message, contains('完整'));
        }
      },
    );
  }

  test(
    'cancellation closes an active session and permits a later request',
    () async {
      final ast = await LocalAst.open('wait');
      addTearDown(ast.close);
      final service = ast.service();
      final task = service.translate(
        wav: wav,
        apiKey: 'test',
        englishSource: true,
      );
      final expectation = expectLater(
        task,
        throwsA(isA<OnlineTranslationException>()),
      );
      await ast.started.future;
      service.cancel();
      await expectation;
      await ast.peerClosed.future.timeout(const Duration(seconds: 3));
      expect(ast.sockets.first.readyState, isNot(WebSocket.open));
      ast.behavior = 'multi';
      final next = await service.translate(
        wav: wav,
        apiKey: 'test',
        englishSource: true,
      );
      expect(next.translation, '左舷主机半速后退。请避让我船。');
    },
  );

  test('rejects invalid key/audio before connecting', () async {
    var calls = 0;
    final service = DoubaoS2tService(
      connector: (_) async {
        calls++;
        throw StateError('Unexpected network');
      },
    );
    await expectLater(
      service.translate(wav: wav, apiKey: 'key\r\nheader', englishSource: true),
      throwsA(isA<OnlineTranslationException>()),
    );
    await expectLater(
      service.translate(
        wav: Uint8List(100),
        apiKey: 'test',
        englishSource: true,
      ),
      throwsA(isA<OnlineTranslationException>()),
    );
    expect(calls, 0);
  });
}
