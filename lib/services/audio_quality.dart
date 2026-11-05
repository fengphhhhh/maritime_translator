import 'dart:typed_data';

/// A conservative energy gate, not a speech/noise classifier. Keep quiet speech
/// and never cut leading/trailing syllables. Reject only near-digital silence.
abstract final class AudioQuality {
  static bool hasAudibleFrames(Uint8List pcm) {
    final data = ByteData.sublistView(pcm);
    const frameBytes = 640; // 20 ms at 16 kHz, mono PCM16.
    var audible = 0;
    for (var start = 0; start + frameBytes <= pcm.length; start += frameBytes) {
      var squares = 0.0;
      for (var i = start; i < start + frameBytes; i += 2) {
        final sample = data.getInt16(i, Endian.little) / 32768;
        squares += sample * sample;
      }
      if (squares / 320 > 0.00000063) audible++; // approximately -62 dBFS.
    }
    return audible >= 3;
  }
}
