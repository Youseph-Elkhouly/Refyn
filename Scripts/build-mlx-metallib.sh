#!/bin/sh
# SwiftPM does not compile MLX's Metal kernels. Build its bundled kernels and
# stage them beside executable binaries, where MLX's loader looks first.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BIN_DIR=$(cd "$ROOT_DIR" && swift build --show-bin-path)
DEST_DIR=${1:-$BIN_DIR}
MLX_SOURCE="$ROOT_DIR/.build/checkouts/mlx-swift/Source/Cmlx/mlx"
MLX_BUILD="$ROOT_DIR/.build/mlx-metal"

command -v cmake >/dev/null || { echo "CMake is required to build MLX Metal kernels" >&2; exit 1; }
command -v xcrun >/dev/null || { echo "Xcode command-line tools are required to build MLX Metal kernels" >&2; exit 1; }
[ -d "$MLX_SOURCE" ] || { echo "Resolve Swift packages before building the MLX Metal library" >&2; exit 1; }

cmake -S "$MLX_SOURCE" -B "$MLX_BUILD" \
  -DMLX_BUILD_TESTS=OFF \
  -DMLX_BUILD_EXAMPLES=OFF \
  -DMLX_BUILD_BENCHMARKS=OFF \
  -DMLX_BUILD_PYTHON_BINDINGS=OFF \
  -DMLX_BUILD_CUDA=OFF \
  -DMLX_BUILD_GGUF=OFF \
  -DMLX_BUILD_SAFETENSORS=OFF \
  -DMLX_METAL_JIT=ON \
  -DMLX_BUILD_METAL=ON
cmake --build "$MLX_BUILD" --target mlx-metallib -j "$(sysctl -n hw.ncpu)"

METALLIB="$MLX_BUILD/mlx/backend/metal/kernels/mlx.metallib"
mkdir -p "$DEST_DIR" "$BIN_DIR"
cp "$METALLIB" "$DEST_DIR/mlx.metallib"
cp "$METALLIB" "$BIN_DIR/mlx.metallib"

for TEST_BUNDLE in "$BIN_DIR"/*PackageTests.xctest/Contents/MacOS; do
  [ -d "$TEST_BUNDLE" ] && cp "$METALLIB" "$TEST_BUNDLE/mlx.metallib"
done
echo "Staged MLX Metal kernels at $DEST_DIR/mlx.metallib"
