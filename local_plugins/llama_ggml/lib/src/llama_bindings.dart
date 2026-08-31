import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _LoadNative =
    Int64 Function(Pointer<Utf8>, Int32, Int32, Int32);
typedef _LoadDart = int Function(Pointer<Utf8>, int, int, int);

typedef _GenerateNative =
    Pointer<Utf8> Function(Int64, Pointer<Utf8>, Int32, Float, Uint32);
typedef _GenerateDart =
    Pointer<Utf8> Function(int, Pointer<Utf8>, int, double, int);

typedef _ReleaseNative = Void Function(Int64);
typedef _ReleaseDart = void Function(int);

typedef _StringFreeNative = Void Function(Pointer<Utf8>);
typedef _StringFreeDart = void Function(Pointer<Utf8>);

typedef _StringGetterNative = Pointer<Utf8> Function();
typedef _StringGetterDart = Pointer<Utf8> Function();

/// The C entry points in `llama_ggml.h`.
///
/// Resolved per isolate: each isolate that touches the model does its own
/// lookup, which is cheap next to anything llama.cpp does.
class LlamaBindings {
  LlamaBindings._(DynamicLibrary library)
    : load = library.lookupFunction<_LoadNative, _LoadDart>('llama_ggml_load'),
      generate = library.lookupFunction<_GenerateNative, _GenerateDart>(
        'llama_ggml_generate',
      ),
      release = library.lookupFunction<_ReleaseNative, _ReleaseDart>(
        'llama_ggml_release',
      ),
      freeString = library.lookupFunction<_StringFreeNative, _StringFreeDart>(
        'llama_ggml_string_free',
      ),
      lastError = library
          .lookupFunction<_StringGetterNative, _StringGetterDart>(
            'llama_ggml_last_error',
          ),
      devices = library.lookupFunction<_StringGetterNative, _StringGetterDart>(
        'llama_ggml_devices',
      );

  factory LlamaBindings.open() => LlamaBindings._(_openLibrary());

  final _LoadDart load;
  final _GenerateDart generate;
  final _ReleaseDart release;
  final _StringFreeDart freeString;
  final _StringGetterDart lastError;
  final _StringGetterDart devices;

  String takeLastError() {
    final String message = lastError().toDartString();
    return message.isEmpty ? 'unknown llama.cpp error' : message;
  }
}

DynamicLibrary _openLibrary() {
  final String? override = Platform.environment['LLAMA_GGML_LIBRARY'];
  if (override != null && override.isNotEmpty) {
    return DynamicLibrary.open(override);
  }
  // iOS/macOS: static pod — symbols are in the main executable.
  return DynamicLibrary.process();
}
