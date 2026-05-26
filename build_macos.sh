#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${1:-${SCRIPT_DIR}/build}"
BUILD_TYPE="${CMAKE_BUILD_TYPE:-Release}"

if ! command -v cmake >/dev/null 2>&1; then
  echo "cmake is required. Install it with Homebrew or from https://cmake.org/download/." >&2
  exit 1
fi

if ! xcrun -sdk macosx metal -v >/dev/null 2>&1; then
  echo "Apple's Metal toolchain is missing." >&2
  echo "Install it with: xcodebuild -downloadComponent MetalToolchain" >&2
  exit 1
fi

cmake -S "${SCRIPT_DIR}" -B "${BUILD_DIR}" -DCMAKE_BUILD_TYPE="${BUILD_TYPE}"
cmake --build "${BUILD_DIR}" --parallel
cmake --build "${BUILD_DIR}" \
  --target spektrafilmDownloadZip spektrafilm_flowDownloadZip \
  --parallel

echo "Built spektrafilm flow, spektrafilm, and spektrafilm dev OFX bundles in ${BUILD_DIR} (${BUILD_TYPE})"
echo "Packaged website downloads:"
echo "  ${REPO_ROOT}/website/public/downloads/spektrafilm_flow-OFX-macOS.zip"
echo "  ${REPO_ROOT}/website/public/downloads/spektrafilm-OFX-macOS.zip"
echo "Install with: cmake --install ${BUILD_DIR}"
