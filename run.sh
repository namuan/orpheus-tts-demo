#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"

echo "==> Building OrpheusUIApp..."
swift build --configuration debug

# Find the architecture-specific build directory
ARCH_DIR=$(ls -d "$BUILD_DIR"/*/debug 2>/dev/null | head -1)
if [ -z "$ARCH_DIR" ]; then
    # Fallback: try common paths
    if [ -d "$BUILD_DIR/debug" ]; then
        ARCH_DIR="$BUILD_DIR/debug"
    else
        echo "ERROR: Could not find build output directory"
        exit 1
    fi
fi

METALLIB="$ARCH_DIR/mlx.metallib"

# Create a minimal stub metallib if it doesn't exist.
# Even with CPU mode (Device.setDefault(device: .cpu)), MLX still needs
# a valid metallib to pass the initial device detection check on Apple Silicon.
# The app runs on CPU via Accelerate framework — GPU JIT compilation is broken
# in swift build because mlx-swift's SPM target excludes key kernel sources
# (rms_norm, layer_norm, rope) from its JIT embedding path.
if [ ! -f "$METALLIB" ]; then
    echo "==> Creating stub Metal library (macOS JIT-compiles kernels at runtime)..."
    TMPDIR=$(mktemp -d)
    cat > "$TMPDIR/stub.metal" << 'METALEOF'
#include <metal_stdlib>
using namespace metal;

kernel void mlx_stub(device float* buf [[buffer(0)]], uint idx [[thread_position_in_grid]]) {
    buf[idx] = 0.0f;
}
METALEOF
    xcrun -sdk macosx metal -c "$TMPDIR/stub.metal" -o "$TMPDIR/stub.air"
    xcrun -sdk macosx metallib "$TMPDIR/stub.air" -o "$METALLIB"
    rm -rf "$TMPDIR"
    echo "   -> Created $METALLIB"
fi

echo "==> Launching Orpheus TTS..."
ORPHEUS_USE_CPU=1 exec "$ARCH_DIR/OrpheusUIApp"
