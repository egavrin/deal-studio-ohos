#!/usr/bin/env bash
# Cross-builds dealer's C ABI (crates/dealer-ffi) for the phone and copies the static library and
# dealer.h to entry/src/main/cpp/dealer, where CMakeLists.txt links them into libdealer.so.
#
#   tools/build-dealer.sh            # DEALER_DIR defaults to ../dealer beside this repository
#   DEALER_DIR=/path/to/dealer OHOS_NATIVE=/path/to/ohos_sdk/26/native tools/build-dealer.sh
#
# Needs rustup (the toolchain comes from dealer's rust-toolchain.toml) and the OpenHarmony native
# SDK's clang, which also builds the SQLite bundled into the library. Delete entry/.cxx once after
# the first run so CMake sees the library.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
dealer="${DEALER_DIR:-$here/../dealer}"
if [ ! -f "$dealer/crates/dealer-ffi/include/dealer.h" ]; then
  echo "build-dealer: no dealer checkout with crates/dealer-ffi at $dealer (set DEALER_DIR)" >&2
  exit 1
fi

native="${OHOS_NATIVE:-}"
if [ -z "$native" ]; then
  for candidate in "$HOME"/agent-kit-sdk/ohos_sdk/*/native; do
    [ -x "$candidate/llvm/bin/aarch64-unknown-linux-ohos-clang" ] && native="$candidate"
  done
fi
clang="$native/llvm/bin/aarch64-unknown-linux-ohos-clang"
if [ ! -x "$clang" ]; then
  echo "build-dealer: no OpenHarmony clang at ${native:-<not found>} (set OHOS_NATIVE)" >&2
  exit 1
fi

export PATH="$HOME/.cargo/bin:$PATH"
target=aarch64-unknown-linux-ohos
(
  cd "$dealer"
  rustup target add "$target" >/dev/null
  CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER="$clang" \
  CC_aarch64_unknown_linux_ohos="$clang" \
  AR_aarch64_unknown_linux_ohos="$native/llvm/bin/llvm-ar" \
    cargo build -p dealer-ffi --release --locked --target "$target"
)

out="$here/entry/src/main/cpp/dealer"
mkdir -p "$out/lib" "$out/include"
cp "$dealer/target/$target/release/libdealer_ffi.a" "$out/lib/"
cp "$dealer/crates/dealer-ffi/include/dealer.h" "$out/include/"
echo "build-dealer: $(git -C "$dealer" rev-parse --short HEAD) -> $out"
