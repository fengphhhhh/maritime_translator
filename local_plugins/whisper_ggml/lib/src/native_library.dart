import 'dart:ffi';
import 'dart:io';

/// Opens the whisper_ggml native library for the current platform.
///
/// On iOS/macOS the pod is statically linked into the app executable, so FFI
/// symbols are resolved via [DynamicLibrary.process].
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
  return DynamicLibrary.process();
}
