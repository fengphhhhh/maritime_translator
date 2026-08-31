#!/usr/bin/env bash
#
# Vendors llama.cpp into ios/Classes/llama/ and prepares it for CocoaPods.
#
# CocoaPods has no equivalent of llama.cpp's CMake build: every file matched by
# the podspec's source_files glob is compiled for every architecture, with one
# set of flags. So the tree has to be trimmed to the backends we build (CPU +
# Metal) and the architecture-specific sources have to guard themselves.
#
#   ./tool/vendor_llama_cpp.sh [version]
#
# Pinned to a build whose ggml is byte-identical to the one whisper.cpp v1.9.1
# vendors, so the two plugins in this app run the same tensor library.
set -euo pipefail

version="${1:-b9700}"
plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="$plugin_root/ios/Classes/llama"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "==> fetching llama.cpp $version"
curl -fsSL "https://github.com/ggml-org/llama.cpp/archive/refs/tags/$version.tar.gz" \
  | tar -xz -C "$work"
src="$(echo "$work"/llama.cpp-*)"

echo "==> copying ggml, llama core and public headers"
rm -rf "$dest"
mkdir -p "$dest"
cp -r "$src/ggml/include" "$dest/ggml-include"
cp -r "$src/ggml/src"     "$dest/ggml"
cp -r "$src/src"          "$dest/src"
cp -r "$src/include"      "$dest/include"
cp    "$src/LICENSE"      "$plugin_root/LICENSE"

echo "==> dropping backends this pod does not build"
for backend in blas cann cuda hexagon hip musa opencl openvino rpc sycl \
               virtgpu vulkan webgpu zdnn zendnn; do
  rm -rf "$dest/ggml/ggml-$backend" "$dest/ggml-include/ggml-$backend.h"
done

echo "==> dropping non-Apple CPU variants"
for arch in loongarch powerpc riscv s390 wasm; do
  rm -rf "$dest/ggml/ggml-cpu/arch/$arch"
done
rm -rf "$dest/ggml/ggml-cpu/cmake" "$dest/ggml/ggml-cpu/kleidiai" "$dest/ggml/ggml-cpu/spacemit"
# Only reachable under GGML_USE_LLAMAFILE, which this pod does not define.
rm -f "$dest/ggml/ggml-cpu/llamafile/sgemm.cpp"

echo "==> dropping build files that would confuse the pod"
find "$dest" -name CMakeLists.txt -delete
find "$dest" -name '*.cmake' -delete

# Upstream compiles these only for the matching architecture. Here they are
# handed to the compiler on every slice, so each file has to be inert unless
# it is being built for its own architecture.
guard_file() {
  local file="$1" condition="$2"
  [ -f "$file" ] || { echo "expected to guard a file that is not there: $file" >&2; exit 1; }
  {
    echo "// vendored patch: whole-file arch guard (sources are compiled on"
    echo "// every architecture in this build system, unlike upstream CMake)"
    echo "$condition"
    cat "$file"
    echo
    echo "#endif // arch guard"
  } > "$file.guarded"
  mv "$file.guarded" "$file"
}

echo "==> applying architecture guards"
arm='#if defined(__aarch64__) || defined(__arm__) || defined(_M_ARM) || defined(_M_ARM64)'
x86='#if defined(__x86_64__) || defined(__i386__) || defined(_M_IX86) || defined(_M_X64)'
for f in cpu-feats.cpp quants.c repack.cpp; do
  guard_file "$dest/ggml/ggml-cpu/arch/arm/$f" "$arm"
  guard_file "$dest/ggml/ggml-cpu/arch/x86/$f" "$x86"
done

echo "==> generating the embedded Metal shader"
"$plugin_root/tool/gen_metal_embed.sh"

echo
echo "vendored llama.cpp $version into $dest"
