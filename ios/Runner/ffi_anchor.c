#include <stdint.h>

// Native anchor so the static linker pulls Dart FFI entry points out of the
// whisper_ggml / llama_ggml pods (they are never called from ObjC/Swift).

extern char *request(char *body);
extern char *stream_start(char *body);
extern char *stream_feed(const float *pcm, int32_t n_samples);
extern char *stream_stop(void);

extern int64_t llama_ggml_load(const char *model_path, int32_t n_ctx,
                               int32_t n_gpu_layers, int32_t n_threads);
extern char *llama_ggml_generate(int64_t handle, const char *prompt,
                                 int32_t max_tokens, float temperature,
                                 uint32_t seed);
extern void llama_ggml_release(int64_t handle);
extern void llama_ggml_string_free(char *text);
extern const char *llama_ggml_last_error(void);
extern const char *llama_ggml_devices(void);

__attribute__((used)) static void *const kFfiAnchorTable[] = {
    (void *)&request,
    (void *)&stream_start,
    (void *)&stream_feed,
    (void *)&stream_stop,
    (void *)&llama_ggml_load,
    (void *)&llama_ggml_generate,
    (void *)&llama_ggml_release,
    (void *)&llama_ggml_string_free,
    (void *)&llama_ggml_last_error,
    (void *)&llama_ggml_devices,
};
