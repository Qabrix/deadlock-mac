#!/bin/zsh
# LLVM 15.0.7, x86_64, static libs only: DXMT's airconv (DXBC -> Metal AIR) links it into
# winemetal.so. Installs to $DL_ROOT/build/llvm15/install; sources/objects are removed after.
set -euo pipefail
source "${0:A:h}/build-env.sh"
D="$DL_ROOT/build/llvm15"
[[ -f $D/install/lib/libLLVMCore.a ]] && { ok "LLVM 15 already built"; exit 0; }
mkdir -p "$D" && cd "$D"
tar=llvm-project-15.0.7.src.tar.xz
[[ -f $tar ]] || curl -fL -o $tar https://github.com/llvm/llvm-project/releases/download/llvmorg-15.0.7/$tar
[[ $(shasum -a 256 $tar | cut -d' ' -f1) == 8b5fcb24b4128cf04df1b0b9410ce8b1a729cb3c544e6da885d234280dedeac6 ]] || die "LLVM sha256 mismatch"
[[ -d llvm-project-15.0.7.src ]] || tar -xf $tar
cmake -B build -S llvm-project-15.0.7.src/llvm -G Ninja \
  -DCMAKE_INSTALL_PREFIX="$D/install" -DCMAKE_OSX_ARCHITECTURES=x86_64 -DLLVM_HOST_TRIPLE=x86_64-apple-darwin \
  -DLLVM_ENABLE_ASSERTIONS=On -DLLVM_ENABLE_ZSTD=Off -DCMAKE_BUILD_TYPE=Release -DLLVM_TARGETS_TO_BUILD="" \
  -DLLVM_BUILD_TOOLS=Off -DLLVM_INCLUDE_TESTS=Off -DLLVM_INCLUDE_BENCHMARKS=Off -DLLVM_INCLUDE_EXAMPLES=Off \
  -DBUG_REPORT_URL="https://github.com/3Shain/dxmt" -DPACKAGE_VENDOR="DXMT" -DLLVM_VERSION_PRINTER_SHOW_HOST_TARGET_INFO=Off
nice -n 10 cmake --build build -j 6
cmake --install build
rm -rf build llvm-project-15.0.7.src
ok "LLVM 15 -> $D/install"
