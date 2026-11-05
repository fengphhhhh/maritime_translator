import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../config/maritime_domain_glossary.dart';
import 'doubao_protocol.dart';
import 'translation_checks.dart';

class OnlineTranslationException implements Exception {
  const OnlineTranslationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class OnlineTranslation {
  const OnlineTranslation(this.source, this.translation, {this.transcript});
  final String source, translation;
  final String? transcript;
}

typedef DoubaoConnector = Future<WebSocket> Function(
  Map<String, String> headers,
);

/// A recorded WAV is streamed to AST after release, following the official demo.
/// No local model, retry, alternate host, or fallback upload is involved.
class DoubaoS2tService {
  DoubaoS2tService({
    this.connector,
    this.responseTimeout = const Duration(seconds: 30),
    this.packetInterval = const Duration(milliseconds: 80),
    this.transcriptOnly = false,
  });

  final DoubaoConnector? connector;
  final Duration responseTimeout, packetInterval;

  /// The chained pipeline needs the final ASR text even if AST's translation
  /// is missing or inaccurate. Standalone S2T keeps its existing validation.
  final bool transcriptOnly;
  _OnlineOperation? _active;

  Future<OnlineTranslation> translate({
    required Uint8List wav,
    required String apiKey,
    required bool englishSource,
    String hotwordTableId = '',
    String glossaryTableId = '',
    void Function(OnlineTranslation partial)? onUpdate,
  }) async {
    if (_active != null) {
      throw const OnlineTranslationException('上一段在线翻译仍在处理中，请稍候。');
    }
    if (apiKey.trim().isEmpty ||
        apiKey.length > 4096 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(apiKey)) {
      throw const OnlineTranslationException('请先在在线设置中保存有效的 API Key。');
    }
    if (wav.length <= 44 || wav.length > 32000 * 120 + 44) {
      throw const OnlineTranslationException('录音为空或超过两分钟，请分段说话。');
    }
    final header = ByteData.sublistView(wav);
    if (String.fromCharCodes(wav.take(4)) != 'RIFF' ||
        String.fromCharCodes(wav.sublist(8, 12)) != 'WAVE' ||
        header.getUint16(20, Endian.little) != 1 ||
        header.getUint16(22, Endian.little) != 1 ||
        header.getUint32(24, Endian.little) != 16000 ||
        header.getUint16(34, Endian.little) != 16 ||
        header.getUint32(40, Endian.little) != wav.length - 44) {
      throw const OnlineTranslationException('录音格式不符合在线翻译要求，请重新录音。');
    }
    final operation = _OnlineOperation();
    _active = operation;
    StreamIterator<dynamic>? incoming;
    Future<void>? sender;
    final source = _Subtitles(english: englishSource);
    final target = _Subtitles(english: !englishSource);
    final sessionId = _uuid();
    final deadline = Timer(
      Duration(
        milliseconds:
            wav.length * 1000 ~/ 32000 + responseTimeout.inMilliseconds + 12000,
      ),
      () {
        operation.expired = true;
        operation.cancel();
      },
    );
    var finishSent = false;
    Object? sendError;

    void checkActive() {
      if (operation.cancelled) {
        if (operation.expired) throw TimeoutException('Online deadline');
        throw const OnlineTranslationException('在线翻译已取消。');
      }
    }

    try {
      final headers = <String, String>{
        'X-Api-Key': apiKey.trim(),
        'X-Api-Resource-Id': DoubaoProtocol.resourceId,
        'X-Api-Connect-Id': _uuid(),
      };
      final WebSocket socket;
      final connect = connector;
      if (connect != null) {
        socket = await connect(headers).timeout(const Duration(seconds: 12));
      } else {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 12);
        operation.client = client;
        socket =
            await WebSocket.connect(
              DoubaoProtocol.endpoint,
              headers: headers,
              customClient: client,
              compression: CompressionOptions.compressionOff,
            ).timeout(
              const Duration(seconds: 12),
              onTimeout: () {
                client.close(force: true);
                throw TimeoutException('Connection timeout');
              },
            );
      }
      operation.socket = socket;
      checkActive();
      socket.pingInterval = const Duration(seconds: 15);
      incoming = StreamIterator(socket);

      Future<DoubaoResponse> receive() async {
        checkActive();
        if (!await incoming!.moveNext().timeout(responseTimeout)) {
          throw const OnlineTranslationException('在线连接提前断开，请检查网络后重试。');
        }
        checkActive();
        final data = incoming!.current;
        if (data is! List<int> || data.length > 1024 * 1024) {
          throw const FormatException('Unexpected online response');
        }
        final response = DoubaoResponse.decode(data);
        if (response.sessionId.isNotEmpty && response.sessionId != sessionId) {
          throw const FormatException('Unexpected session');
        }
        if (response.event == 151 ||
            response.event == 153 ||
            !const {0, 21000, 20000000}.contains(response.status)) {
          // Never echo the provider's raw message or a handshake exception:
          // those can contain request details. The numeric code is sufficient.
          throw OnlineTranslationException(
            '豆包会话失败（错误码 ${response.status}）。请检查密钥、服务开通状态及额度。',
          );
        }
        return response;
      }

      final glossary = <String, String>{};
      for (final entry in MaritimeDomainGlossary.entries.entries.take(96)) {
        glossary.putIfAbsent(
          englishSource ? entry.key : entry.value,
          () => englishSource ? entry.value : entry.key,
        );
      }
      final hotwords = <String>{
        'VTS',
        'VHF',
        'CPA',
        'UKC',
        'ETA',
        'SWL',
        ...glossary.keys.take(64),
      }.toList();
      socket.add(
        DoubaoProtocol.start(
          sessionId,
          englishSource: englishSource,
          hotwords: hotwordTableId.isEmpty ? hotwords : const [],
          glossary: glossaryTableId.isEmpty ? glossary : const {},
          boostingTableId: hotwordTableId,
          glossaryTableId: glossaryTableId,
        ),
      );
      final accepted = await receive();
      if (accepted.event != 150) {
        throw const OnlineTranslationException('豆包未确认会话建立，请稍后重试。');
      }

      Future<void> sendAudio() async {
        const packetBytes =
            2560; // 80 ms PCM16, retaining the initial WAV header.
        for (var offset = 0; offset < wav.length; offset += packetBytes) {
          checkActive();
          if (operation.stopped) return;
          socket.add(
            DoubaoProtocol.audio(
              sessionId,
              Uint8List.sublistView(
                wav,
                offset,
                min(offset + packetBytes, wav.length),
              ),
            ),
          );
          await Future<void>.delayed(packetInterval);
        }
        checkActive();
        if (operation.stopped) return;
        finishSent = true;
        socket.add(DoubaoProtocol.finish(sessionId));
      }

      sender = sendAudio().catchError((Object error) {
        sendError = error;
        unawaited(socket.close().catchError((Object _) {}));
      });
      var receivedMessages = 0;
      while (true) {
        final response = await receive();
        if (++receivedMessages > 10000) {
          throw const FormatException('Too many subtitle messages');
        }
        if (response.event == 152) {
          if (!finishSent ||
              !source.isFinal ||
              (!transcriptOnly && !target.isFinal)) {
            throw const OnlineTranslationException('豆包未返回完整的原文和译文，请重试。');
          }
          break;
        }
        switch (response.event) {
          case 650:
            source.start();
          case 651:
            source.partial(response.text);
          case 652:
            source.end(response.text);
          case 653:
            target.start();
          case 654:
            target.partial(response.text);
          case 655:
            target.end(response.text);
        }
        if (source.text.length + target.text.length > 32000) {
          throw const FormatException('Subtitle limit exceeded');
        }
        if (response.event >= 650 && response.event <= 655) {
          onUpdate?.call(OnlineTranslation(source.text, target.text));
        }
      }
      await sender;
      if (sendError != null) throw sendError!;
      checkActive();
      final result = OnlineTranslation(source.text.trim(), target.text.trim());
      if (result.source.isEmpty ||
          (!transcriptOnly && result.translation.isEmpty)) {
        throw const OnlineTranslationException('没有收到完整语音翻译结果，请重新说话。');
      }
      if (!transcriptOnly &&
          !TranslationChecks.preservesNumbers(
            result.source,
            result.translation,
          )) {
        throw const OnlineTranslationException('在线译文的数字与原文不一致，请核对原文后重试。');
      }
      if (!transcriptOnly &&
          !TranslationChecks.preservesCriticalMeaning(
            result.source,
            result.translation,
          )) {
        throw const OnlineTranslationException('在线译文的左右舷、车钟或否定指令需核对，请重试。');
      }
      return result;
    } on OnlineTranslationException {
      rethrow;
    } on TimeoutException {
      throw const OnlineTranslationException('在线翻译超时，请检查网络，或手动切换到离线模式。');
    } on FormatException {
      throw const OnlineTranslationException('豆包响应格式异常，请稍后重试。');
    } on Object {
      throw const OnlineTranslationException(
        '无法完成在线翻译，请检查网络、API Key及服务开通状态，或手动切换离线。',
      );
    } finally {
      deadline.cancel();
      operation.stopped = true;
      operation.close();
      if (incoming != null) await incoming.cancel();
      if (sender != null) await sender;
      if (identical(_active, operation)) _active = null;
    }
  }

  void cancel() {
    final operation = _active;
    _active = null;
    operation?.cancel();
  }

  static String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final s = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }
}

class _OnlineOperation {
  bool cancelled = false, stopped = false, expired = false;
  WebSocket? socket;
  HttpClient? client;
  void cancel() {
    cancelled = true;
    close();
  }

  void close() {
    stopped = true;
    client?.close(force: true);
    final ws = socket;
    if (ws != null) unawaited(ws.close().catchError((Object _) {}));
  }
}

/// End events are authoritative sentence snapshots; never append a final
/// sentence to its provisional subtitle. Different sentences remain separate.
class _Subtitles {
  _Subtitles({required this.english});
  final bool english;
  final List<String> _complete = [];
  String _current = '';
  bool _open = false;
  bool get isFinal => !_open && _complete.isNotEmpty;
  String get text => [
    ..._complete,
    if (_current.isNotEmpty) _current,
  ].join(english ? ' ' : '');
  void start() {
    if (_open && _current.isNotEmpty) {
      throw const FormatException('Unfinished subtitle segment');
    }
    _current = '';
    _open = true;
  }

  void partial(String text) {
    _open = true;
    _current = text.startsWith(_current) ? text : _current + text;
  }

  void end(String text) {
    final sentence = (text.isNotEmpty ? text : _current).trim();
    if (sentence.isNotEmpty &&
        (_open || _complete.isEmpty || _complete.last != sentence)) {
      _complete.add(sentence);
    }
    _current = '';
    _open = false;
  }
}
