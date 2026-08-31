#include "llama_ggml.h"

#include "ggml-backend.h"
#include "llama.h"

#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

namespace {

struct session {
    llama_model         * model = nullptr;
    llama_context       * ctx   = nullptr;
    const llama_vocab   * vocab = nullptr;
    // llama_decode is not reentrant on one context, and Dart may well call
    // from a different isolate than the one that loaded the model.
    std::mutex            mutex;
};

// Per-thread so a failure reported to one isolate cannot be overwritten by
// another isolate before it is read.
thread_local std::string t_last_error;

void set_error(std::string message) {
    t_last_error = std::move(message);
}

void ensure_backend_init() {
    static std::once_flag once;
    std::call_once(once, [] { llama_backend_init(); });
}

session * as_session(int64_t handle) {
    return reinterpret_cast<session *>(static_cast<intptr_t>(handle));
}

std::string piece_for(const llama_vocab * vocab, llama_token token) {
    char buf[256];
    const int32_t n = llama_token_to_piece(vocab, token, buf, sizeof(buf), 0, /*special=*/false);
    if (n >= 0) {
        return std::string(buf, n);
    }
    // Rare: a token whose text does not fit the stack buffer.
    std::string out(static_cast<size_t>(-n), '\0');
    const int32_t written = llama_token_to_piece(vocab, token, out.data(), -n, 0, /*special=*/false);
    if (written < 0) {
        return {};
    }
    out.resize(static_cast<size_t>(written));
    return out;
}

char * to_heap(const std::string & text) {
    char * copy = static_cast<char *>(std::malloc(text.size() + 1));
    if (copy == nullptr) {
        return nullptr;
    }
    std::memcpy(copy, text.c_str(), text.size() + 1);
    return copy;
}

} // namespace

int64_t llama_ggml_load(const char * model_path, int32_t n_ctx, int32_t n_gpu_layers, int32_t n_threads) {
    t_last_error.clear();

    if (model_path == nullptr || *model_path == '\0') {
        set_error("model path is empty");
        return 0;
    }

    ensure_backend_init();

    llama_model_params mparams = llama_model_default_params();
    mparams.n_gpu_layers = n_gpu_layers;

    llama_model * model = llama_model_load_from_file(model_path, mparams);
    if (model == nullptr) {
        set_error(std::string("failed to load model: ") + model_path);
        return 0;
    }

    llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx = static_cast<uint32_t>(n_ctx > 0 ? n_ctx : 2048);
    // One prompt is submitted per call and it is short, so the logical batch
    // only has to be large enough to swallow it in a single llama_decode.
    cparams.n_batch         = cparams.n_ctx;
    cparams.n_ubatch        = 512;
    cparams.n_threads       = n_threads > 0 ? n_threads : 4;
    cparams.n_threads_batch = cparams.n_threads;

    llama_context * ctx = llama_init_from_model(model, cparams);
    if (ctx == nullptr) {
        llama_model_free(model);
        set_error("failed to create llama context");
        return 0;
    }

    auto * s = new session();
    s->model = model;
    s->ctx   = ctx;
    s->vocab = llama_model_get_vocab(model);

    return static_cast<int64_t>(reinterpret_cast<intptr_t>(s));
}

char * llama_ggml_generate(
    int64_t      handle,
    const char * prompt,
    int32_t      max_tokens,
    float        temperature,
    uint32_t     seed) {
    t_last_error.clear();

    session * s = as_session(handle);
    if (s == nullptr) {
        set_error("invalid session handle");
        return nullptr;
    }
    if (prompt == nullptr) {
        set_error("prompt is null");
        return nullptr;
    }

    std::lock_guard<std::mutex> lock(s->mutex);

    // Each call is a standalone request. Without this the previous
    // translation stays in the KV cache and conditions the next one.
    llama_memory_clear(llama_get_memory(s->ctx), /*data=*/true);

    const int32_t prompt_len = static_cast<int32_t>(std::strlen(prompt));

    // parse_special: the ChatML control tokens in the prompt have to become
    // real tokens rather than literal angle-bracket text.
    int32_t n_prompt = -llama_tokenize(s->vocab, prompt, prompt_len, nullptr, 0, /*add_special=*/false, /*parse_special=*/true);
    if (n_prompt <= 0) {
        set_error("prompt tokenized to nothing");
        return nullptr;
    }

    std::vector<llama_token> tokens(static_cast<size_t>(n_prompt));
    if (llama_tokenize(s->vocab, prompt, prompt_len, tokens.data(), n_prompt, false, true) < 0) {
        set_error("failed to tokenize prompt");
        return nullptr;
    }

    const int32_t n_ctx = static_cast<int32_t>(llama_n_ctx(s->ctx));
    if (n_prompt >= n_ctx) {
        set_error("prompt is longer than the context window");
        return nullptr;
    }

    if (llama_decode(s->ctx, llama_batch_get_one(tokens.data(), n_prompt)) != 0) {
        set_error("failed to evaluate the prompt");
        return nullptr;
    }

    llama_sampler * sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
    if (temperature > 0.0f) {
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40));
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9f, 1));
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature));
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(seed));
    } else {
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy());
    }

    std::string out;
    int32_t     n_decoded = 0;
    const int32_t budget = max_tokens > 0 ? max_tokens : 256;

    while (n_decoded < budget && n_prompt + n_decoded < n_ctx) {
        const llama_token token = llama_sampler_sample(sampler, s->ctx, -1);
        if (llama_vocab_is_eog(s->vocab, token)) {
            break;
        }

        out += piece_for(s->vocab, token);
        n_decoded++;

        llama_token next = token;
        if (llama_decode(s->ctx, llama_batch_get_one(&next, 1)) != 0) {
            llama_sampler_free(sampler);
            set_error("failed to evaluate a generated token");
            return nullptr;
        }
    }

    llama_sampler_free(sampler);

    char * result = to_heap(out);
    if (result == nullptr) {
        set_error("out of memory building the result");
    }
    return result;
}

void llama_ggml_release(int64_t handle) {
    session * s = as_session(handle);
    if (s == nullptr) {
        return;
    }
    // Not taking s->mutex: releasing while a generation is in flight is a
    // caller bug, and blocking here would only turn it into a deadlock.
    if (s->ctx != nullptr) {
        llama_free(s->ctx);
    }
    if (s->model != nullptr) {
        llama_model_free(s->model);
    }
    delete s;
}

void llama_ggml_string_free(char * text) {
    std::free(text);
}

const char * llama_ggml_last_error(void) {
    return t_last_error.c_str();
}

const char * llama_ggml_devices(void) {
    static std::mutex  mutex;
    static std::string cached;

    std::lock_guard<std::mutex> lock(mutex);
    if (!cached.empty()) {
        return cached.c_str();
    }

    ensure_backend_init();

    const size_t count = ggml_backend_dev_count();
    for (size_t i = 0; i < count; i++) {
        ggml_backend_dev_t dev = ggml_backend_dev_get(i);
        if (dev == nullptr) {
            continue;
        }
        if (!cached.empty()) {
            cached += ",";
        }
        const char * name = ggml_backend_dev_name(dev);
        cached += name != nullptr ? name : "?";
    }
    if (cached.empty()) {
        cached = "none";
    }
    return cached.c_str();
}
