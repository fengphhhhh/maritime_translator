#!/usr/bin/env bash
#
# Regenerates ggml-metal-embed.metal, the single self-contained Metal source
# that gets baked into the binary by ggml-metal-embed.s.
#
# ggml-metal.metal is not compilable on its own: it pulls in ggml-common.h
# (through the __embed_ggml-common.h__ marker) and ggml-metal-impl.h, and
# MTLDevice's newLibraryWithSource: has no include path to resolve either.
# Upstream solves this in CMake (GGML_METAL_EMBED_LIBRARY); CocoaPods has no
# equivalent hook for a local pod, so we run the same two substitutions ahead
# of time and commit the result.
#
# Re-run after bumping the vendored whisper.cpp/ggml sources:
#   ./tool/gen_metal_embed.sh
set -euo pipefail

metal_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../ios/Classes/llama/ggml/ggml-metal" && pwd)"

source_metal="$metal_dir/ggml-metal.metal"
common_header="$metal_dir/../ggml-common.h"
impl_header="$metal_dir/ggml-metal-impl.h"
output="$metal_dir/ggml-metal-embed.metal"

for required in "$source_metal" "$common_header" "$impl_header"; do
  [ -f "$required" ] || { echo "missing input: $required" >&2; exit 1; }
done

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# 1. inline ggml-common.h in place of the embed marker
sed -e "/__embed_ggml-common.h__/r $common_header" \
    -e "/__embed_ggml-common.h__/d" \
    < "$source_metal" > "$tmp"

# 2. inline ggml-metal-impl.h in place of its #include
sed -e "/#include \"ggml-metal-impl.h\"/r $impl_header" \
    -e "/#include \"ggml-metal-impl.h\"/d" \
    < "$tmp" > "$output"

if grep -q '__embed_ggml-common.h__' "$output"; then
  echo "embed marker survived the substitution" >&2
  exit 1
fi

# A local #include left on a live line would fail at runtime, where the Metal
# compiler has no search path to resolve it. Exactly one survives on purpose:
# the `#else` arm of the embed guard, which is dead because ggml defines
# GGML_METAL_EMBED_LIBRARY when it compiles this source.
remaining="$(grep -cE '^\s*#\s*include\s+"' "$output" || true)"
dead_branch="$(grep -B1 -E '^\s*#\s*include\s+"ggml-common\.h"' "$output" | head -1)"
if [ "$remaining" != "1" ] || [ "$dead_branch" != "#else" ]; then
  echo "unexpected local #include left in $output:" >&2
  grep -nE '^\s*#\s*include\s+"' "$output" >&2
  exit 1
fi

echo "wrote $output ($(wc -c < "$output") bytes)"
