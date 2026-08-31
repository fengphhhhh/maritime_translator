#import "LlamaGgmlPlugin.h"

#include "llama_ggml.h"

@implementation LlamaGgmlPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  static int64_t (*const anchor_load)(const char *, int32_t, int32_t, int32_t) =
      llama_ggml_load;
  static char *(*const anchor_generate)(int64_t, const char *, int32_t, float,
                                        uint32_t) = llama_ggml_generate;
  static void (*const anchor_release)(int64_t) = llama_ggml_release;
  static void (*const anchor_string_free)(char *) = llama_ggml_string_free;
  static const char *(*const anchor_last_error)(void) = llama_ggml_last_error;
  static const char *(*const anchor_devices)(void) = llama_ggml_devices;
  (void)anchor_load;
  (void)anchor_generate;
  (void)anchor_release;
  (void)anchor_string_free;
  (void)anchor_last_error;
  (void)anchor_devices;
}

@end
