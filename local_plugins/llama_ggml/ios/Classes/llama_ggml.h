// C ABI over llama.cpp, sized for one job: turn a fully-formed prompt into a
// short completion, on device.
//
// Everything here is deliberately synchronous and blocking. Dart calls it from
// a worker isolate, so there is no callback plumbing and no shared state to
// get wrong beyond the session handle itself.

#ifndef LLAMA_GGML_H
#define LLAMA_GGML_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LLAMA_GGML_API __attribute__((visibility("default"))) __attribute__((used))

// Loads a GGUF model and creates a context for it.
//
// n_gpu_layers is passed straight to llama.cpp: 0 keeps everything on the CPU,
// a large value (99) offloads the whole model to Metal.
//
// Returns an opaque handle, or 0 on failure — call llama_ggml_last_error for
// the reason. The handle owns several hundred MB and must be handed to
// llama_ggml_release.
LLAMA_GGML_API int64_t llama_ggml_load(
    const char * model_path,
    int32_t      n_ctx,
    int32_t      n_gpu_layers,
    int32_t      n_threads);

// Runs the prompt through the model and returns the completion.
//
// The context memory is cleared first, so each call is independent: no text
// and no KV state carries over from the previous one.
//
// temperature <= 0 selects greedy decoding, which is what makes a translation
// reproducible. Generation stops at an end-of-generation token, after
// max_tokens, or when the context is full.
//
// Returns a heap string the caller must pass to llama_ggml_string_free, or
// NULL on failure.
LLAMA_GGML_API char * llama_ggml_generate(
    int64_t      handle,
    const char * prompt,
    int32_t      max_tokens,
    float        temperature,
    uint32_t     seed);

// Frees the model and context behind handle. Safe to call with 0.
LLAMA_GGML_API void llama_ggml_release(int64_t handle);

// Frees a string returned by llama_ggml_generate.
LLAMA_GGML_API void llama_ggml_string_free(char * text);

// Why the last call on this thread failed. Empty when nothing has failed.
LLAMA_GGML_API const char * llama_ggml_last_error(void);

// The ggml backends that registered themselves, e.g. "Metal,CPU". The caller
// can use this to confirm the GPU backend is actually present rather than
// assuming it from the build flags. Never NULL.
LLAMA_GGML_API const char * llama_ggml_devices(void);

#ifdef __cplusplus
}
#endif

#endif // LLAMA_GGML_H
