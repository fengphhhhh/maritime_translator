import 'dart:convert';
import 'dart:typed_data';

/// Minimal protobuf wire codec for the official AST 2.0 schema, not JSON/TTS.
/// Field numbers are verified against the official downloadable client protos.
abstract final class DoubaoProtocol {
  static const endpoint =
      'wss://openspeech.bytedance.com/api/v4/ast/v2/translate';
  static const resourceId = 'volc.service_type.10053';

  static Uint8List start(
    String sessionId, {
    required bool englishSource,
    List<String> hotwords = const [],
    Map<String, String> glossary = const {},
    String boostingTableId = '',
    String glossaryTableId = '',
  }) {
    if (hotwords.length + glossary.length > 1000) {
      throw const FormatException('Too many corpus entries');
    }
    final corpus = ProtoWriter();
    if (boostingTableId.isNotEmpty) corpus.string(2, boostingTableId);
    if (glossaryTableId.isNotEmpty) corpus.string(14, glossaryTableId);
    for (final word in hotwords) {
      corpus.string(9, word);
    }
    for (final term in glossary.entries) {
      final entry = ProtoWriter()
        ..string(1, term.key)
        ..string(2, term.value);
      corpus.bytes(10, entry.build());
    }
    final params = ProtoWriter()
      ..string(1, 's2t')
      ..string(2, englishSource ? 'en' : 'zh')
      ..string(3, englishSource ? 'zh' : 'en');
    if (hotwords.isNotEmpty ||
        glossary.isNotEmpty ||
        boostingTableId.isNotEmpty ||
        glossaryTableId.isNotEmpty) {
      params.bytes(100, corpus.build());
    }
    final audio = ProtoWriter()
      ..string(4, 'wav')
      ..string(5, 'raw')
      ..integer(7, 16000)
      ..integer(8, 16)
      ..integer(9, 1);
    final meta = ProtoWriter()..string(6, sessionId);
    return (ProtoWriter()
          ..bytes(1, meta.build())
          ..integer(2, 100)
          ..bytes(4, audio.build())
          ..bytes(6, params.build()))
        .build();
  }

  static Uint8List audio(String sessionId, Uint8List data) {
    final audio = ProtoWriter()..bytes(14, data);
    return (ProtoWriter()
          ..bytes(1, (ProtoWriter()..string(6, sessionId)).build())
          ..integer(2, 200)
          ..bytes(4, audio.build()))
        .build();
  }

  static Uint8List finish(String sessionId) =>
      (ProtoWriter()
            ..bytes(1, (ProtoWriter()..string(6, sessionId)).build())
            ..integer(2, 102))
          .build();
}

class DoubaoResponse {
  const DoubaoResponse({
    required this.event,
    this.text = '',
    this.status = 0,
    this.sessionId = '',
    this.startTime = 0,
    this.endTime = 0,
  });
  final int event, status, startTime, endTime;
  final String text, sessionId;

  factory DoubaoResponse.decode(List<int> data) {
    final fields = ProtoReader(Uint8List.fromList(data)).fields();
    final meta = fields[1] is Uint8List
        ? ProtoReader(fields[1] as Uint8List).fields()
        : <int, Object>{};
    String string(Object? value) =>
        value is Uint8List ? utf8.decode(value) : '';
    return DoubaoResponse(
      event: fields[2] as int? ?? 0,
      text: string(fields[4]),
      status: meta[3] as int? ?? 0,
      sessionId: string(meta[1]),
      startTime: fields[5] as int? ?? 0,
      endTime: fields[6] as int? ?? 0,
    );
  }
}

class ProtoWriter {
  final _bytes = BytesBuilder(copy: false);
  void _varint(int value) {
    if (value < 0) throw const FormatException('Negative protobuf integer');
    while (value > 127) {
      _bytes.addByte((value & 127) | 128);
      value >>= 7;
    }
    _bytes.addByte(value);
  }

  void integer(int field, int value) {
    _varint(field << 3);
    _varint(value);
  }

  void bytes(int field, List<int> value) {
    _varint((field << 3) | 2);
    _varint(value.length);
    _bytes.add(value);
  }

  void string(int field, String value) => bytes(field, utf8.encode(value));
  Uint8List build() => _bytes.toBytes();
}

class ProtoReader {
  ProtoReader(this.data);
  final Uint8List data;
  int _offset = 0;
  int _varint() {
    var value = 0;
    for (var shift = 0; shift < 64; shift += 7) {
      if (_offset >= data.length) {
        throw const FormatException('Truncated protobuf');
      }
      final byte = data[_offset++];
      value |= (byte & 127) << shift;
      if (byte < 128) return value;
    }
    throw const FormatException('Invalid protobuf varint');
  }

  Map<int, Object> fields() {
    final result = <int, Object>{};
    while (_offset < data.length) {
      final tag = _varint(), field = tag >> 3, wire = tag & 7;
      if (field == 0) throw const FormatException('Invalid protobuf field');
      switch (wire) {
        case 0:
          result[field] = _varint();
        case 2:
          final length = _varint();
          if (length < 0 || length > data.length - _offset) {
            throw const FormatException('Truncated protobuf bytes');
          }
          result[field] = Uint8List.sublistView(
            data,
            _offset,
            _offset + length,
          );
          _offset += length;
        case 1:
          _offset += 8;
        case 5:
          _offset += 4;
        default:
          throw const FormatException('Unsupported protobuf wire type');
      }
      if (_offset > data.length) {
        throw const FormatException('Truncated protobuf');
      }
    }
    return result;
  }
}
