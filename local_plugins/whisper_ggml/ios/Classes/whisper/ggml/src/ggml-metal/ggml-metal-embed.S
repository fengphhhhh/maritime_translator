// Bakes the merged Metal shader source into the binary.
//
// ggml-metal-device.m declares these two symbols when GGML_METAL_EMBED_LIBRARY
// is defined and compiles the bytes between them with newLibraryWithSource:,
// passing the macros that match the device (bf16, tensor). That is why the
// shader is embedded as source rather than a precompiled default.metallib: a
// metallib has to commit to one feature set at build time, and it also has to
// be found in a bundle at runtime.
//
// Uppercase .S so clang preprocesses the file first: the path below is a macro
// and can be overridden from the build settings if the assembler's include
// search path ever fails to resolve the bare name.
//
// Regenerate the embedded source with tool/gen_metal_embed.sh.

#ifndef GGML_METAL_EMBED_PATH
#define GGML_METAL_EMBED_PATH "ggml-metal-embed.metal"
#endif

.section __DATA,__ggml_metallib

.globl _ggml_metallib_start
_ggml_metallib_start:
.incbin GGML_METAL_EMBED_PATH
.globl _ggml_metallib_end
_ggml_metallib_end:
