// C ABI exported to Dart FFI on iOS. Must keep default visibility when the pod
// is built with -fvisibility=hidden / GCC_SYMBOLS_PRIVATE_EXTERN.

#ifndef WHISPER_GGML_FFI_H
#define WHISPER_GGML_FFI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(__GNUC__) || defined(__clang__)
#define WHISPER_GGML_FFI_API \
  __attribute__((visibility("default"))) __attribute__((used))
#else
#define WHISPER_GGML_FFI_API
#endif

WHISPER_GGML_FFI_API char *request(char *body);

WHISPER_GGML_FFI_API char *stream_start(char *body);

WHISPER_GGML_FFI_API char *stream_feed(const float *pcm, int32_t n_samples);

WHISPER_GGML_FFI_API char *stream_stop(void);

#ifdef __cplusplus
}
#endif

#endif // WHISPER_GGML_FFI_H
