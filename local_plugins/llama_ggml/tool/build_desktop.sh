#!/usr/bin/env bash
#
# Builds the vendored sources into a plain shared library for this machine.
#
# Two things it is good for, neither of which needs a Mac:
#   - proving the tree the podspec globs actually compiles and links, with no
#     duplicate or undefined symbols;
#   - running tool/../../../tool/prompt_smoke_test.dart against a real model,
#     so prompt changes can be judged before they reach a phone.
#
# CPU only: the Metal backend is skipped, since it needs Apple frameworks.
#
#   ./tool/build_desktop.sh
#   LLAMA_GGML_LIBRARY=build/desktop/libllama_ggml.so dart run ...
#
# Override the compiler flags with LLAMA_GGML_CFLAGS for a faster (less
# portable) build, e.g. LLAMA_GGML_CFLAGS="-O3 -fPIC -w -march=native".
set -euo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="$plugin_root/ios/Classes"
out="$plugin_root/build/desktop"
mkdir -p "$out/obj"

INC="-I$root/llama/include -I$root/llama/ggml-include -I$root/llama/ggml -I$root/llama/ggml/ggml-cpu -I$root/llama/src -I$root"
DEF='-DNDEBUG -DGGML_USE_CPU=1 -DGGML_VERSION="b9700" -DGGML_COMMIT="b9700"'
FLAGS="${LLAMA_GGML_CFLAGS:--O2 -fPIC -w}"

mapfile -t sources < <(
  find "$root/llama/ggml" -path "$root/llama/ggml/ggml-metal" -prune -o \
       \( -name '*.c' -o -name '*.cpp' \) -print
  find "$root/llama/src" -name '*.cpp'
  echo "$root/llama_ggml.cpp"
)

echo "compiling ${#sources[@]} sources"
for src in "${sources[@]}"; do
  obj="$out/obj/$(echo "${src#"$root"/}" | tr '/' '_').o"
  if [[ "$src" == *.c ]]; then
    gcc $FLAGS $DEF $INC -std=gnu11 -D_GNU_SOURCE -c "$src" -o "$obj" &
  else
    g++ $FLAGS $DEF $INC -std=c++20 -c "$src" -o "$obj" &
  fi
  while [ "$(jobs -rp | wc -l)" -ge "$(nproc)" ]; do wait -n; done
done
wait

echo "linking"
g++ -shared -o "$out/libllama_ggml.so" "$out"/obj/*.o -lpthread -lm -ldl
echo "built $out/libllama_ggml.so ($(du -h "$out/libllama_ggml.so" | cut -f1))"
