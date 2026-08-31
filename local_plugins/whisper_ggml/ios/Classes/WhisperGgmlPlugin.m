#import "WhisperGgmlPlugin.h"

#include "whisper_ggml_ffi.h"

@implementation WhisperGgmlPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  static char *(*const anchor_request)(char *) = request;
  static char *(*const anchor_stream_start)(char *) = stream_start;
  static char *(*const anchor_stream_feed)(const float *, int32_t) = stream_feed;
  static char *(*const anchor_stream_stop)(void) = stream_stop;
  (void)anchor_request;
  (void)anchor_stream_start;
  (void)anchor_stream_feed;
  (void)anchor_stream_stop;
}

@end
