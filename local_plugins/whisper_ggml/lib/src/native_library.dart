import 'dart:ffi';
import 'dart:io';

/// Opens the whisper_ggml native library for the current platform.
///
/// On iOS the pod is a dynamic framework; FFI symbols live in
/// `whisper_ggml.framework`, not the main executable, so
/// [DynamicLibrary.process] cannot resolve `request`.
DynamicLibrary openWhisperGgmlLibrary() {
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libwhisper.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('whisper_ggml.dll');
  }
  if (Platform.isLinux) {
    return DynamicLibrary.open('libwhisper_ggml.so');
  }
  if (Platform.isIOS) {
    const paths = [
      'whisper_ggml.framework/whisper_ggml',
      'Frameworks/whisper_ggml.framework/whisper_ggml',
    ];
    Object? lastError;
    for (final path in paths) {
      try {
        return DynamicLibrary.open(path);
      } on Object catch (error) {
        lastError = error;
      }
    }
    throw ArgumentError(
      'Could not open whisper_ggml.framework on iOS: $lastError',
    );
  }
  return DynamicLibrary.process();
}
