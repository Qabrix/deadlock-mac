#!/bin/zsh
# Release builds of the pieces we compile ourselves, for every Apple-silicon Mac on macOS 15+: deployment target 15.0
# (also for the Metal shader library, which otherwise targets the build machine's macOS) and the M1's instruction set
# (armv8.4-a: LSE atomics, nothing newer). Builds in APFS clones of the working trees, so a maintainer's own tuned
# builds stay as they are. Pauses while Deadlock runs (the build would take the game's CPU and power).
#   maintainer/build-public.sh [rosetta-dxmt|arm64-dxmt|arm64-wine|arm64-fex|all]
# Needs the trees maintainer/build-runtimes.sh sets up under $DL_ROOT/build (Wine, DXMT + patches/dxmt, neutron).
# Output: $DL_ROOT/build/public/out/<piece>/ (maintainer/package.sh collects them).
set -u
here=${0:A:h}
source "${here:h}/lib/common.sh"
B=$DL_ROOT/build W=$B/arm64/work P=$B/public O=$B/public/out
MIN=15.0 MARCH=armv8.4-a
PROF=$DL_ROOT/pgo/dxmt.profdata
LLVM_MINGW=$W/toolchains/llvm-mingw-20260908-ucrt-macos-universal/bin
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # Metal compiler
export MACOSX_DEPLOYMENT_TARGET=$MIN
mkdir -p "$P" "$O"

wait_closed() { local said=0; while game_running; do (( said++ )) || print "waiting for Deadlock to exit…"; sleep 15; done; }
guarded() {   # name command...: own process group, stopped while the game runs
  local name=$1; shift
  wait_closed
  local st="$P/.$name.status"; rm -f "$st"
  perl -e 'setpgrp(0, 0); exec @ARGV' zsh -c 'st=$1; shift; "$@"; print $? > "$st"' x "$st" "$@" &
  local pid=$! paused=0
  while kill -0 $pid 2>/dev/null; do
    if game_running; then (( paused )) || { kill -STOP -$pid; paused=1; print "game started: build paused"; }
    elif (( paused )); then kill -CONT -$pid; paused=0; print "game closed: build resumed"; fi
    sleep 3
  done
  [[ -f $st && $(<"$st") == 0 ]] || die "$name failed"
}
# clone <src> <dst>: an APFS copy of a working tree, refreshed from the source on every run (sources only, build
# dirs stay)
clone() {
  local src=$1 dst=$2
  [[ -d $dst ]] || { cp -c -R "$src" "$dst" || die "clone of $src failed"; return 0; }
  rsync -a --delete --exclude '/build*/' "$src/" "$dst/"
}
# DXMT's own shader library: compiled for macOS $MIN instead of the build machine's macOS
metal_target() {   # metal_target <dxmt tree>
  grep -q "air64-apple-macos$MIN" "$1/src/dxmt/meson.build" && return 0
  perl -0pi -e "s/dxmt_shaders_ir = metalir_generator.process\(dxmt_shaders\)/dxmt_shaders_ir = metalir_generator.process(dxmt_shaders, extra_args: ['--target=air64-apple-macos$MIN'])/" "$1/src/dxmt/meson.build"
  grep -q "air64-apple-macos$MIN" "$1/src/dxmt/meson.build" || die "could not set the Metal target in $1"
}
check_min() {   # check_min <file>...: every Mach-O targets macOS <= $MIN
  local f v
  for f in "$@"; do
    v=$(otool -l "$f" | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print $2; exit}')
    [[ ${v%%.*} -le ${MIN%%.*} ]] || die "${f:t} targets macOS $v"
  done
}

what=${1:-all}

if [[ $what == (rosetta-dxmt|all) ]]; then
  S=$P/dxmt-src BD=$P/dxmt-build-rosetta OUT=$O/rosetta-dxmt
  clone "$B/dxmt-src" "$S"; metal_target "$S"
  if [[ ! -d $BD ]]; then
    f="'-march=x86-64-v2','-fprofile-use=$PROF','-Wno-profile-instr-unprofiled','-Wno-profile-instr-out-of-date','-Wno-backend-plugin'"
    (cd "$S" && meson setup --cross-file "$B/dxmt-win64-clang.txt" --native-file "$B/dxmt-native-x86_64.txt" \
      -Dnative_llvm_path="$B/llvm15/install" -Dwine_build_path="$B/obj-winecx-wine1117-e0aa3807/wine" \
      -Denable_nvapi=true -Denable_nvngx=true --buildtype release -Db_lto=true -Db_lto_mode=thin \
      "-Dc_args=[$f]" "-Dcpp_args=[$f]" \
      "-Dbuild.c_args=['-arch','x86_64','-march=x86-64-v2']" "-Dbuild.cpp_args=['-arch','x86_64','-march=x86-64-v2']" \
      "$BD") || die "meson setup failed"
  fi
  guarded rosetta-dxmt meson compile -C "$BD"
  rm -rf "$OUT"; mkdir -p "$OUT/x86_64-windows" "$OUT/x86_64-unix"
  find "$BD/src" -name '*.dll' \( -name 'd3d11.dll' -o -name 'dxgi.dll' -o -name 'd3d10core.dll' \
    -o -name 'winemetal.dll' -o -name 'nvapi64.dll' -o -name 'nvngx.dll' \) -exec cp -f {} "$OUT/x86_64-windows/" \;
  find "$BD/src" -name 'winemetal.so' -exec cp -f {} "$OUT/x86_64-unix/" \;
  ln -sfn ../../wine/x86_64-unix/ntdll.so "$OUT/x86_64-unix/ntdll.so"
  ln -sfn ../../wine/x86_64-unix/winemac.so "$OUT/x86_64-unix/winemac.so"
  check_min "$OUT/x86_64-unix/winemetal.so"
  print "$(git -C "$B/dxmt-src" rev-parse --short HEAD) + patches/dxmt, macOS $MIN, PGO" > "$OUT/.version"
  ok "Rosetta DXMT -> $OUT"
fi

if [[ $what == (arm64-dxmt|all) ]]; then
  export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:$LLVM_MINGW:$PATH"
  S=$P/dxmt-arm64-src BD=$P/dxmt-build-arm64 BP=$P/dxmt-build-arm64ec-pure OUT=$O/arm64-dxmt
  clone "$B/arm64/dxmt-ours-arm64-v2" "$S"; metal_target "$S"
  common=(-Dnative_llvm_path="$W/toolchains/llvm-darwin-arm64" -Dwine_install_path="$W/wine-sdk"
          -Denable_nvapi=true -Denable_nvngx=true --buildtype release --strip)
  if [[ ! -d $BD ]]; then
    pf="'-fprofile-use=$PROF','-Wno-profile-instr-unprofiled'"
    (cd "$S" && meson setup --cross-file build-arm64ec.txt "-Dc_args=['-marm64x','-march=$MARCH',$pf]" \
      "-Dcpp_args=['-marm64x','-march=$MARCH',$pf]" $common --prefix "$P/dxmt-arm64-install" "$BD") || die "meson setup failed"
  fi
  guarded arm64-dxmt zsh -c "meson compile -C '$BD' && meson install -C '$BD'"
  # nvngx.dll as pure ARM64EC (PE machine AMD64): the game's NGX loader rejects an ARM64X core
  if [[ ! -d $BP ]]; then
    (cd "$S" && meson setup --cross-file build-arm64ec.txt "-Dc_args=['-march=$MARCH']" "-Dcpp_args=['-march=$MARCH']" \
      '-Dc_link_args=[]' '-Dcpp_link_args=[]' $common "$BP") || die "meson setup (nvngx) failed"
  fi
  guarded arm64-nvngx meson compile -C "$BP" nvngx postprocess_libnvngx
  rm -rf "$OUT"; mkdir -p "$OUT"
  for f in d3d11 dxgi d3d10core winemetal nvapi64; do cp -p "$P/dxmt-arm64-install/aarch64-windows/$f.dll" "$OUT/"; done
  cp -p "$P/dxmt-arm64-install/aarch64-unix/winemetal.so" "$BP/src/nvngx/nvngx.dll" "$OUT/"
  check_min "$OUT/winemetal.so"
  ok "ARM64 DXMT -> $OUT"
fi

if [[ $what == (arm64-wine|all) ]]; then
  export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:$LLVM_MINGW:$PATH"
  BD=$P/wine-build OUT=$O/arm64-wine
  # the build tree refers to its source by path, so a clone of the build dir builds the same source with other flags
  [[ -d $BD ]] || cp -c -R "$W/wine-build" "$BD"
  sed -i '' -E "s/-march=armv8\.[0-9]+-a/-march=$MARCH/g" "$BD/Makefile"
  grep -q -- "-march=$MARCH" "$BD/Makefile" || sed -i '' -E "s/^((aarch64|arm64ec)_C(XX)?FLAGS = .*)$/\1 -march=$MARCH/" "$BD/Makefile"
  # what our patches change (the rest of the runtime is neutron's own build, already macOS 15)
  dirs=(server dlls/ntdll dlls/kernelbase dlls/kernel32 dlls/winemac.drv dlls/win32u dlls/wined3d dlls/d3d9)
  stamp=$BD/.public-$MIN-$MARCH
  [[ -f $stamp ]] || { for d in $dirs; do find "$BD/$d" -name '*.o' -delete; done; }
  targets=(server/wineserver dlls/ntdll/ntdll.so dlls/winemac.drv/winemac.so dlls/win32u/win32u.so
           dlls/ntdll/aarch64-windows/ntdll.dll dlls/kernelbase/aarch64-windows/kernelbase.dll
           dlls/kernel32/aarch64-windows/kernel32.dll dlls/wined3d/aarch64-windows/wined3d.dll dlls/d3d9/aarch64-windows/d3d9.dll)
  guarded arm64-wine make -C "$BD" -j$(sysctl -n hw.ncpu) $targets
  touch "$stamp"
  rm -rf "$OUT"; mkdir -p "$OUT/bin" "$OUT/aarch64-unix" "$OUT/aarch64-windows"
  cp -p "$BD/server/wineserver" "$OUT/bin/"
  for f in dlls/ntdll/ntdll.so dlls/winemac.drv/winemac.so dlls/win32u/win32u.so; do cp -p "$BD/$f" "$OUT/aarch64-unix/"; done
  for f in ${(M)targets:#*.dll}; do cp -p "$BD/$f" "$OUT/aarch64-windows/"; done
  check_min "$OUT/bin/wineserver" "$OUT"/aarch64-unix/*.so
  ok "ARM64 Wine pieces -> $OUT"
fi

if [[ $what == (arm64-fex|all) ]]; then
  export PATH="$LLVM_MINGW:$PATH"
  S=$P/FEX-src EC=$P/fex-arm64ec UL=$P/fex-unixlib OUT=$O/arm64-fex
  if [[ ! -d $S ]]; then
    # a clean checkout of the FEX commit neutron pins, plus exactly the patches in this repo (neutron's macOS port
    # first; it already contains our SMC fix 0001)
    # (an APFS copy of the working tree with its submodules, reset to the commit)
    cp -c -R "$W/src/FEX-main" "$S" && git -C "$S" checkout -q -- . && git -C "$S" clean -qfd || die "FEX checkout failed"
    for p in "$DL_APP"/patches/arm64/arm64-fex-main-with-neutron-macos.patch "$DL_APP"/patches/arm64/arm64-fex-000[2-9]-*.patch; do
      git -C "$S" apply "$p" || die "${p:t} does not apply"
    done
  fi
  if [[ ! -d $EC ]]; then
    cmake -S "$S" -B "$EC" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$S/Data/CMake/toolchain_mingw.cmake" -DMINGW_TRIPLE=arm64ec-w64-mingw32 \
      -DCMAKE_BUILD_TYPE=Release -DENABLE_LTO=False -DBUILD_TESTING=False -DENABLE_ASSERTIONS=False -DBUILD_THUNKS=OFF \
      -DTUNE_ARCH=$MARCH -DTUNE_CPU=none -DCMAKE_C_FLAGS=-DNEUTRON_TEB_IN_TSD \
      "-DCMAKE_CXX_FLAGS=-DNEUTRON_TEB_IN_TSD -DDL_RELAX_UNLISTED -DDL_PAUSE_WFET=1" || die "cmake (FEX ARM64EC) failed"
  fi
  if [[ ! -d $UL ]]; then
    cmake -S "$S/Source/Windows/UnixLib" -B "$UL" -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN -DCMAKE_OSX_ARCHITECTURES=arm64 || die "cmake (FEX unixlib) failed"
  fi
  guarded arm64-fex-ec cmake --build "$EC"
  guarded arm64-fex-unixlib cmake --build "$UL"
  rm -rf "$OUT"; mkdir -p "$OUT"
  cp -p "$EC/Bin/libarm64ecfex.dll" "$UL/libarm64ecfex.so" "$OUT/"
  check_min "$OUT/libarm64ecfex.so"
  ok "ARM64 FEX -> $OUT"
fi
