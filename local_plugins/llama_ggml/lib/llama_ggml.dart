import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'src/llama_bindings.dart';

class LlamaException implements Exception {
  const LlamaException(this.message);

  final String message;

  @override
  String toString() => 'LlamaException: $message';
}

/// A GGUF model loaded into memory, with a context to run it in.
///
/// Loading costs seconds and a gigabyte or so of RAM, so a session is meant to
/// be kept across requests and released deliberately — see [release].
///
/// Every call hops to a worker isolate: llama.cpp blocks its calling thread
/// for the whole of a decode, which on the UI isolate would freeze the app.
class LlamaSession {
  LlamaSession._(this._handle);

  final int _handle;
  bool _released = false;

  /// Loads [modelPath] and prepares a context of [contextSize] tokens.
  ///
  /// [gpuLayers] is how many transformer layers to offload to Metal; the
  /// default offloads all of them. Pass 0 to stay on the CPU.
  static Future<LlamaSession> load(
    String modelPath, {
    int contextSize = 2048,
    int gpuLayers = 99,
    int threads = 4,
  }) async {
    final int handle = await Isolate.run(
      () => _loadSync(modelPath, contextSize, gpuLayers, threads),
    );
    return LlamaSession._(handle);
  }

  /// Completes [prompt] and returns the generated text.
  ///
  /// The context is cleared first, so calls do not condition one another.
  /// A [temperature] of 0 means greedy decoding, which keeps a given input
  /// translating to the same output every time.
  Future<String> generate(
    String prompt, {
    int maxTokens = 256,
    double temperature = 0,
    int seed = 0,
  }) {
    if (_released) {
      throw const LlamaException('session has already been released');
    }
    final int handle = _handle;
    return Isolate.run(
      () => _generateSync(handle, prompt, maxTokens, temperature, seed),
    );
  }

  /// Frees the model and its context. The session cannot be used afterwards.
  ///
  /// iOS terminates a backgrounded app that is holding on to this much
  /// memory, so callers are expected to release rather than wait for the
  /// process to end.
  Future<void> release() async {
    if (_released) return;
    _released = true;
    final int handle = _handle;
    await Isolate.run(() => _releaseSync(handle));
  }

  /// The ggml backends that registered, e.g. `Metal,CPU`.
  ///
  /// Reports what the process actually has rather than what the build flags
  /// asked for, which is the only way to confirm Metal came up.
  static Future<String> devices() => Isolate.run(_devicesSync);
}

int _loadSync(String modelPath, int contextSize, int gpuLayers, int threads) {
  final LlamaBindings bindings = LlamaBindings.open();
  final Pointer<Utf8> path = modelPath.toNativeUtf8();
  try {
    final int handle = bindings.load(path, contextSize, gpuLayers, threads);
    if (handle == 0) {
      throw LlamaException(bindings.takeLastError());
    }
    return handle;
  } finally {
    calloc.free(path);
  }
}

String _generateSync(
  int handle,
  String prompt,
  int maxTokens,
  double temperature,
  int seed,
) {
  final LlamaBindings bindings = LlamaBindings.open();
  final Pointer<Utf8> nativePrompt = prompt.toNativeUtf8();
  try {
    final Pointer<Utf8> result = bindings.generate(
      handle,
      nativePrompt,
      maxTokens,
      temperature,
      seed,
    );
    if (result == nullptr) {
      throw LlamaException(bindings.takeLastError());
    }
    try {
      return result.toDartString();
    } finally {
      bindings.freeString(result);
    }
  } finally {
    calloc.free(nativePrompt);
  }
}

void _releaseSync(int handle) => LlamaBindings.open().release(handle);

String _devicesSync() => LlamaBindings.open().devices().toDartString();
