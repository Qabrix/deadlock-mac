#!/bin/zsh
# Build a relocatable x86_64 Wine runtime (+ MoltenVK, DXVK for Steam's UI, DXMT).
#
#   maintainer/build-wine.sh                      build (resumes; finished stages are skipped)
#   maintainer/build-wine.sh --clean              wipe this Wine source's build dirs first
#   WINECX_COMMIT=<sha> maintainer/build-wine.sh   move the winecx pin
#
# The tree runs under Rosetta (configure/make/Wine's own tools are x86_64), but the
# compilers are native: clang via an arm64 wrapper, mingw-w64 GCC from arm64 Homebrew.
# Deps (gmp, nettle, gnutls, freetype) come from the CrossOver source drop and get bundled
# into <runtime>/lib, so nothing points at Homebrew or the build dir afterwards.
set -euo pipefail
HERE=${0:A:h}
source "$HERE/build-env.sh"

CX_VERSION=${CX_VERSION:-26.3.0}
CX_URL="https://media.codeweavers.com/pub/crossover/source/crossover-sources-$CX_VERSION.tar.gz"
BUILD="$DL_ROOT/build"
TARBALL="$BUILD/crossover-sources-$CX_VERSION.tar.gz"
SRC="$BUILD/src-$CX_VERSION/sources"
OBJ="$BUILD/obj-$CX_VERSION"            # deps, DXVK (shared by every Wine source)
DEPS="$BUILD/deps-$CX_VERSION"          # x86_64 prefix for the bundled libs
OBJ_WINE="$BUILD/obj-$WINE_ID/wine"
OUT="$WINE_HOME"
LOGDIR="$BUILD/logs-$WINE_ID"
case $DL_WINE in
  winecx)    WINE_SRC="$BUILD/winecx-$WINECX_BRANCH"; PATCHES="$HERE/../patches/wine-rosetta" ;;
esac
DXMT_VERSION=0.80
DXMT_URL="https://github.com/3Shain/dxmt/releases/download/v$DXMT_VERSION/dxmt-v$DXMT_VERSION-builtin.tar.gz"
DXMT_SHA256=8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d
# DXMT main: the CI artifact of one commit (building needs Xcode's Metal compiler), fetched
# via nightly.link since GitHub artifact downloads need a login. -> lib/dxmt-next.
DXMT_NEXT_COMMIT=186a2327f1ec76376f6bc1ef64636f08b0728567
DXMT_NEXT_RUN=38211702924
DXMT_NEXT_SHA256=e87334134d16a0a5143cda6fbbec8b243f43be8a7032405490d7836a82eb4aab
# Gcenx's DXVK-macOS (1.10.3 + MoltenVK fallbacks, e.g. no geometry shaders). CrossOver's
# copy of DXVK assumes CrossOver's own MoltenVK fork and rejects every feature level on
# stock MoltenVK, which leaves Steam's web UI without a D3D11 device.
DXVK_REPO=https://github.com/Gcenx/DXVK-macOS.git
DXVK_TAG=v1.10.3-20230507-repack
DXVK_COMMIT=8f1e28deed3ad30802f7e1bdff428ec14e6e7817
MVK_VERSION=1.4.2
MVK_URL="https://github.com/KhronosGroup/MoltenVK/releases/download/v$MVK_VERSION/MoltenVK-macos.tar"
MVK_SHA256=f95765a6229cb7b915990a2890ce12ebe36a730b021545d3d52ae69ce4c4024e
MIN_MACOS=14.0                          # D3DMetal's LSMinimumSystemVersion
JOBS=${JOBS:-$(sysctl -n hw.ncpu)}
BREW=/opt/homebrew

if [[ ${1:-} == --clean ]]; then
  rm -rf "$BUILD/obj-$WINE_ID" "$LOGDIR" "$OUT" "$BUILD"/.done-$WINE_ID-*
  shift
fi

# Re-exec under Rosetta so configure's test programs and Wine's build tools are x86_64.
if [[ $(sysctl -n sysctl.proc_translated 2>/dev/null) != 1 ]]; then
  rosetta_ok || die "Rosetta 2 missing: softwareupdate --install-rosetta --agree-to-license"
  exec /usr/bin/arch -x86_64 /bin/zsh "$0" "$@"
fi

for t in bison flex x86_64-w64-mingw32-gcc i686-w64-mingw32-gcc pkgconf cmake autoreconf meson ninja glslangValidator; do
  [[ -x $BREW/bin/$t || -x $BREW/opt/bison/bin/$t || -x $BREW/opt/flex/bin/$t ]] \
    || die "missing $t: brew install bison flex mingw-w64 pkgconf cmake autoconf automake libtool meson ninja glslang"
done

mkdir -p "$BUILD/bin" "$OBJ" "$DEPS" "$OBJ_WINE" "$LOGDIR"

# Native arm64 clang emitting x86_64 code: same output, no Rosetta tax on the compiler.
cat >"$BUILD/bin/cc-x86_64" <<EOF
#!/bin/sh
exec /usr/bin/arch -arm64 /usr/bin/clang -arch x86_64 -mmacosx-version-min=$MIN_MACOS "\$@"
EOF
chmod +x "$BUILD/bin/cc-x86_64"

export PATH="$BUILD/bin:$BREW/opt/bison/bin:$BREW/opt/flex/bin:$BREW/opt/libtool/libexec/gnubin:$BREW/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export CC="$BUILD/bin/cc-x86_64" OBJC="$BUILD/bin/cc-x86_64"
export CFLAGS="-O2" CPPFLAGS="-I$DEPS/include"
export LDFLAGS="-L$DEPS/lib -Wl,-headerpad_max_install_names"
export PKG_CONFIG=$BREW/bin/pkgconf
export PKG_CONFIG_LIBDIR="$DEPS/lib/pkgconfig"   # never see arm64 Homebrew .pc files
export PKG_CONFIG_PATH=
export MACOSX_DEPLOYMENT_TARGET=$MIN_MACOS
autoconf_host=(--build=x86_64-apple-darwin --host=x86_64-apple-darwin)

CURRENT=""
trap '(( $? )) && [[ -n $CURRENT ]] && print -u2 "✗ stage \"$CURRENT\" failed, see $LOGDIR/$CURRENT.log"' EXIT

# stage <key> <name> <function>: run once, log to file, stamp on success. key is
# $CX_VERSION for deps shared by every Wine source, $WINE_ID for Wine itself.
stage() {
  local name=$2 stamp="$BUILD/.done-$1-$2"
  if [[ -f $stamp ]]; then ok "$name (done earlier)"; return 0; fi
  step "$name"
  CURRENT=$name
  local t0=$SECONDS
  $3 >"$LOGDIR/$name.log" 2>&1
  touch "$stamp"
  CURRENT=""
  ok "$name ($(( SECONDS - t0 ))s)"
}

# ------------------------------------------------------------------- stages
fetch() {  # CrossOver source drop: deps for every build, Wine itself for DL_WINE=crossover
  [[ -f $TARBALL ]] || curl -fL -o "$TARBALL.part" "$CX_URL" && { [[ -f $TARBALL ]] || mv "$TARBALL.part" "$TARBALL"; }
  rm -rf "$BUILD/src-$CX_VERSION"
  mkdir -p "$BUILD/src-$CX_VERSION"
  tar -xzf "$TARBALL" -C "$BUILD/src-$CX_VERSION"
  rm -f "$BUILD/.done-cx$CX_VERSION-patch"   # fresh tree needs patching again
  [[ -f $SRC/wine/configure ]]
}

fetch_git_wine() {  # winecx / yaagl: shallow clone pinned to an exact commit
  local repo commit
  case $DL_WINE in
    winecx) repo=$WINECX_REPO commit=$WINECX_COMMIT ;;
    yaagl)  repo=$YAAGL_REPO  commit=$YAAGL_COMMIT ;;
  esac
  if [[ ! -d $WINE_SRC/.git ]]; then
    rm -rf "$WINE_SRC" && git init -q "$WINE_SRC"
  fi
  if [[ $(git -C "$WINE_SRC" rev-parse HEAD 2>/dev/null) != $commit ]]; then
    git -C "$WINE_SRC" fetch -q --depth 1 "$repo" "$commit"
    git -C "$WINE_SRC" checkout -q --force FETCH_HEAD
    rm -f "$BUILD/.done-$WINE_ID-patch"
  fi
  [[ $(git -C "$WINE_SRC" rev-parse HEAD) == $commit ]]
  print "$DL_WINE @ $commit: $(cat "$WINE_SRC/VERSION")"
}

apply_patches() {  # our patch queue: patches/<source>/*.patch, applied to the Wine tree
  local p
  for p in "$PATCHES"/*.patch(N); do
    if patch -p1 -R -s -f --dry-run -d "$WINE_SRC" < "$p" >/dev/null 2>&1; then
      print "already applied: ${p:t}"; continue
    fi
    print "applying ${p:t}"
    patch -p1 -N -d "$WINE_SRC" < "$p"
  done
}

build_gmp() {
  mkdir -p "$OBJ/gmp" && cd "$OBJ/gmp"
  "$SRC/gnutls/gmp/configure" --prefix="$DEPS" $autoconf_host \
    --enable-shared --disable-static --disable-assembly
  make -j$JOBS && make install
}

build_nettle() {
  # CodeWeavers' nettle copy ships without its (hand-written) Makefile.in files, so build
  # from the upstream release instead, after checking its sources match CX's byte-for-byte.
  local cx="$SRC/gnutls/nettle" ver f
  ver=$(sed -n 's/^AC_INIT(\[nettle\], \[\([0-9.]*\)\].*/\1/p' "$cx/configure.ac")
  local up="$BUILD/nettle-$ver"
  if [[ ! -f $up/Makefile.in ]]; then
    curl -fL -o "$BUILD/nettle-$ver.tar.gz" "https://ftp.gnu.org/gnu/nettle/nettle-$ver.tar.gz"
    rm -rf "$up" && tar -xzf "$BUILD/nettle-$ver.tar.gz" -C "$BUILD"
  fi
  local checked=0
  for f in "$cx"/**/*.(c|h|asm)(.N); do
    # Dev-only helpers in the git tree (e.g. eccparams.c) aren't in release tarballs.
    [[ -e $up/${f#$cx/} ]] || { print "not in release tarball (ok): ${f#$cx/}"; continue; }
    cmp -s "$f" "$up/${f#$cx/}" || { print "nettle mismatch vs CX copy: ${f#$cx/}"; return 1; }
    checked=$(( checked + 1 ))
  done
  print "nettle $ver: $checked source files identical to CrossOver's copy"
  mkdir -p "$OBJ/nettle" && cd "$OBJ/nettle"
  "$up/configure" --prefix="$DEPS" --libdir="$DEPS/lib" $autoconf_host \
    --enable-shared --disable-static --disable-openssl --disable-documentation --enable-fat
  make -j$JOBS && make install
}

build_gnutls() {
  rm -rf "$OBJ/gnutls" && mkdir -p "$OBJ/gnutls" && cd "$OBJ/gnutls"
  # LIBS=-lnettle: configure probes nettle_streebog512_update etc. linking only -lhogweed;
  # Mach-O two-level namespace doesn't pass libnettle's symbols through, so the probe
  # fails and gnutls compiles its own Streebog that clashes with nettle 3.10's headers.
  LIBS=-lnettle "$SRC/gnutls/gnutls/configure" --prefix="$DEPS" $autoconf_host \
    --enable-shared --disable-static \
    --with-included-libtasn1 --with-included-unistring \
    --without-p11-kit --without-idn --without-zstd --without-brotli --without-tpm --without-tpm2 \
    --disable-doc --disable-tests --disable-tools --disable-cxx --disable-nls \
    --disable-libdane --disable-guile --disable-full-test-suite
  make -j$JOBS && make install
}

build_freetype() {
  cmake -S "$SRC/freetype" -B "$OBJ/freetype" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$DEPS" \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_OSX_ARCHITECTURES=x86_64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN_MACOS -DCMAKE_IGNORE_PREFIX_PATH=$BREW \
    -DBUILD_SHARED_LIBS=ON -DCMAKE_INSTALL_NAME_DIR="$DEPS/lib" \
    -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_BROTLI=ON -DFT_DISABLE_PNG=ON \
    -DFT_REQUIRE_ZLIB=ON -DFT_REQUIRE_BZIP2=ON
  cmake --build "$OBJ/freetype" -j$JOBS
  cmake --install "$OBJ/freetype"
}

fetch_moltenvk() {
  # Official Khronos build (CX's own MoltenVK source needs full Xcode). Wine dlopen()s it
  # as libvulkan; it gives us winevulkan, which DXVK (Steam's UI) runs on.
  local tar="$BUILD/MoltenVK-macos-$MVK_VERSION.tar" lib
  if [[ ! -f $tar ]]; then curl -fL -o "$tar.part" "$MVK_URL"; mv "$tar.part" "$tar"; fi
  [[ $(shasum -a 256 "$tar" | cut -d' ' -f1) == $MVK_SHA256 ]] || { rm -f "$tar"; print "sha256 mismatch"; return 1; }
  rm -rf "$BUILD/mvk-$MVK_VERSION" && mkdir -p "$BUILD/mvk-$MVK_VERSION"
  tar -xf "$tar" -C "$BUILD/mvk-$MVK_VERSION"
  lib=$(find "$BUILD/mvk-$MVK_VERSION" -name libMoltenVK.dylib -path '*macOS*' | head -1)
  [[ -n $lib ]] && lipo -archs "$lib" | grep -q x86_64
  lipo "$lib" -thin x86_64 -output "$DEPS/lib/libMoltenVK.dylib" 2>/dev/null || cp -f "$lib" "$DEPS/lib/libMoltenVK.dylib"
  install_name_tool -id "$DEPS/lib/libMoltenVK.dylib" "$DEPS/lib/libMoltenVK.dylib"
  codesign -f -s - "$DEPS/lib/libMoltenVK.dylib"
}

configure_wine() {
  # freetype2.pc "Requires.private: zlib bzip2". The SDK has both libs but ships no .pc
  # files, and PKG_CONFIG_LIBDIR deliberately hides Homebrew's arm64 ones.
  local pc
  for pc in zlib:z bzip2:bz2; do
    print -l "Name: ${pc%%:*}" "Description: macOS SDK ${pc%%:*}" "Version: 1.0" \
      "Libs: -l${pc##*:}" "Cflags:" > "$DEPS/lib/pkgconfig/${pc%%:*}.pc"
  done
  # Newer upstream Wine ships amd_fidelityfx_* DX12 modules whose i386 build fails against
  # their own ffx_api.h (calling-convention mismatch). DX12-only; not needed for DX11 games.
  local wine_disable=() m
  for m in $(grep -oE 'enable_amd_fidelityfx_[a-z0-9_]+' "$WINE_SRC/configure" | sort -u); do
    wine_disable+=(--disable-${m#enable_})
  done
  print "disabled modules: ${wine_disable[*]:-none}"
  # Reconfigure in place: objects that don't change are kept by make.
  mkdir -p "$OBJ_WINE" && cd "$OBJ_WINE"
  "$WINE_SRC/configure" --prefix="$OUT" --enable-archs=i386,x86_64 --disable-tests \
    --with-mingw --with-gnutls --with-freetype --with-coreaudio --with-vulkan \
    --without-x --without-wayland --without-fontconfig --without-alsa --without-oss \
    --without-pulse --without-udev --without-dbus --without-capi --without-gphoto \
    --without-sane --without-v4l2 --without-pcap --without-pcsclite --without-krb5 \
    --without-gssapi --without-netapi --without-usb --without-gstreamer --without-ffmpeg \
    --without-sdl --without-opencl --without-hwloc --without-inotify --without-gettext \
    $wine_disable
  # Fail loudly if a feature we rely on silently dropped out.
  grep -q '^#define SONAME_LIBGNUTLS' include/config.h
  grep -q '^#define SONAME_LIBFREETYPE' include/config.h
  grep -q '^#define SONAME_LIBVULKAN' include/config.h
}

build_wine() {
  cd "$OBJ_WINE"
  make -j$JOBS
}

install_wine() {
  rm -rf "$OUT"
  cd "$OBJ_WINE"
  make install-lib    # runtime only, no headers/man pages
}

bundle_deps() {
  local lib dep
  mkdir -p "$OUT/lib"
  for lib in "$DEPS"/lib/lib{gmp,nettle,hogweed,gnutls,freetype,MoltenVK}*.dylib(.N); do
    cp -f "$lib" "$OUT/lib/"
  done
  # Recreate the version symlinks Wine dlopen()s by leaf name (e.g. libgnutls.30.dylib).
  for lib in "$DEPS"/lib/lib{gmp,nettle,hogweed,gnutls,freetype,MoltenVK}*.dylib(@N); do
    ln -sf "$(readlink "$lib")" "$OUT/lib/${lib:t}"
  done
  for lib in "$OUT"/lib/*.dylib(.N); do
    install_name_tool -id "@rpath/${lib:t}" "$lib"
    for dep in $(otool -L "$lib" | awk 'NR>1{print $1}' | grep -F "$DEPS/lib/" || true); do
      install_name_tool -change "$dep" "@loader_path/${dep:t}" "$lib"
    done
    codesign -f -s - "$lib"   # install_name_tool invalidates the ad-hoc signature
  done
  # Wine dlopen()s these by leaf name from its unix modules. dyld resolves leaf names via
  # the caller's LC_RPATH (@loader_path = lib/wine/x86_64-unix), so link them in there.
  # No DYLD_* env needed: macOS strips those whenever a SIP binary (nohup, sh, env, ...)
  # sits in the launch chain, which is how Steam's child processes lost gnutls.
  for lib in "$OUT"/lib/lib*.dylib(N); do
    ln -sfn "../../${lib:t}" "$OUT/lib/wine/x86_64-unix/${lib:t}"
  done
}

build_dxvk() {
  # Only Steam's web UI uses it: CEF's GPU process crashes on D3DMetal and renders black
  # in software mode (its output can't cross Wine's process boundary on macOS).
  local src="$BUILD/dxvk-macos-src"
  if [[ ! -d $src/.git ]]; then
    rm -rf "$src"
    git clone -q --depth 1 --branch "$DXVK_TAG" "$DXVK_REPO" "$src"
  fi
  [[ $(git -C "$src" rev-parse HEAD) == $DXVK_COMMIT ]] || { print "DXVK commit mismatch"; return 1; }
  if [[ ! -f $OBJ/dxvk-install/x86_64/d3d11.dll ]]; then
  rm -rf "$OBJ/dxvk" "$OBJ/dxvk-install"
  meson setup "$OBJ/dxvk" "$src" --cross-file "$src/build-win64.txt" \
    --buildtype release --prefix "$OBJ/dxvk-install" --bindir x86_64 \
    -Denable_d3d9=false \
    -Dcpp_args="['-include', 'cstdint']"   # DXVK 1.10 predates GCC 13 dropping implicit <cstdint>
  ninja -C "$OBJ/dxvk" install
  fi
  mkdir -p "$OUT/lib/dxvk/x86_64-windows"
  cp -f "$OBJ/dxvk-install/x86_64/"{d3d11,d3d10core,dxgi}.dll "$OUT/lib/dxvk/x86_64-windows/"
}

install_dxmt() {
  # DXMT (D3D11 -> Metal directly). Its Wine half is only the winemetal bridge, which goes
  # into Wine's builtins. Its d3d11/dxgi/d3d10core go to lib/dxmt and are handed to one
  # program via WINE_EXE_DLLPATH; as global builtins they'd break Steam's web UI (DXMT
  # can't present into another process's window).
  local tar="$BUILD/dxmt-v$DXMT_VERSION-builtin.tar.gz" x="$BUILD/dxmt-v$DXMT_VERSION"
  if [[ ! -f $tar ]]; then curl -fL -o "$tar.part" "$DXMT_URL"; mv "$tar.part" "$tar"; fi
  [[ $(shasum -a 256 "$tar" | cut -d' ' -f1) == $DXMT_SHA256 ]] || { rm -f "$tar"; print "sha256 mismatch"; return 1; }
  rm -rf "$x" && mkdir -p "$x" && tar -xzf "$tar" -C "$x"
  local d=$(find "$x" -type d -name x86_64-unix | head -1); d=${d:h}
  [[ -f $d/x86_64-unix/winemetal.so ]]
  cp -f "$d/x86_64-unix/"* "$OUT/lib/wine/x86_64-unix/"
  cp -f "$d/x86_64-windows/winemetal.dll" "$OUT/lib/wine/x86_64-windows/"
  [[ -f $d/i386-windows/winemetal.dll ]] && cp -f "$d/i386-windows/winemetal.dll" "$OUT/lib/wine/i386-windows/"
  mkdir -p "$OUT/lib/dxmt/x86_64-windows"
  find "$d/x86_64-windows" -name '*.dll' ! -name winemetal.dll -exec cp -f {} "$OUT/lib/dxmt/x86_64-windows/" \;
  ls "$OUT/lib/dxmt/x86_64-windows"
}

install_dxmt_next() {
  # Self-contained: d3d11/dxgi/d3d10core/nvapi64/nvngx + its own winemetal.dll and .so. Wine
  # takes a builtin's unix lib from the same dll-path entry, so it never mixes with the
  # release's winemetal in Wine's builtins. ntdll/winemac are linked for winemetal's @rpath.
  local short=${DXMT_NEXT_COMMIT[1,8]} zip x n="$OUT/lib/dxmt-next"
  x="$BUILD/dxmt-$short"; zip="$x/dxmt.zip"; mkdir -p "$x"
  if [[ ! -f $zip ]]; then
    curl -fL -o "$zip.part" "https://nightly.link/3Shain/dxmt/actions/runs/$DXMT_NEXT_RUN/dxmt-$DXMT_NEXT_COMMIT.zip"
    mv "$zip.part" "$zip"
  fi
  [[ $(shasum -a 256 "$zip" | cut -d' ' -f1) == $DXMT_NEXT_SHA256 ]] || { rm -f "$zip"; print "sha256 mismatch"; return 1; }
  rm -rf "$x/t" && mkdir -p "$x/t" && unzip -o -q "$zip" -d "$x/t" && tar -xzf "$x"/t/*.tar.gz -C "$x/t"
  local d="$x/t/$DXMT_NEXT_COMMIT"
  rm -rf "$n" && mkdir -p "$n/x86_64-windows" "$n/x86_64-unix"
  cp -f "$d"/x86_64-windows/*.dll "$n/x86_64-windows/"
  cp -f "$d/x86_64-unix/winemetal.so" "$n/x86_64-unix/"
  ln -sfn ../../wine/x86_64-unix/ntdll.so "$n/x86_64-unix/ntdll.so"
  ln -sfn ../../wine/x86_64-unix/winemac.so "$n/x86_64-unix/winemac.so"
  print $DXMT_NEXT_COMMIT > "$n/.version"
}

verify() {
  local f bad=0
  file "$OUT/bin/wine" | grep -q x86_64
  # Relocatable: no Mach-O in the runtime may reference the build tree or Homebrew.
  for f in "$OUT"/bin/*(.N) "$OUT"/lib/*.dylib(.N) "$OUT"/lib/wine/x86_64-unix/*.so(.N); do
    if otool -L "$f" 2>/dev/null | awk 'NR>1{print $1}' | grep -qE "^($BUILD|$BREW)"; then
      print "non-relocatable: $f"; otool -L "$f"; bad=1
    fi
  done
  (( bad == 0 ))
  strings -a "$OUT/bin/wineserver" | grep -qi msync
  [[ -f $OUT/lib/dxvk/x86_64-windows/d3d11.dll && -e $OUT/lib/wine/x86_64-unix/libMoltenVK.dylib ]]
  [[ -f $OUT/lib/wine/x86_64-unix/winemetal.so && -f $OUT/lib/dxmt/x86_64-windows/d3d11.dll ]]
  # builtin d3d must be Wine's own (D3DMetal/DXMT live in lib/d3dmetal, lib/dxmt)
  ! strings -a "$OUT/lib/wine/x86_64-windows/dxgi.dll" | grep -qiE "d3dmetal|dxmt"
  "$OUT/bin/wine" --version
}

K=$CX_VERSION W=$WINE_ID
stage $K fetch          fetch
[[ $DL_WINE != crossover ]] && { rm -f "$BUILD/.done-$W-fetch-wine"; stage $W fetch-wine fetch_git_wine; }
stage $W patch          apply_patches
stage $K gmp            build_gmp
stage $K nettle         build_nettle
stage $K gnutls         build_gnutls
stage $K freetype       build_freetype
stage $K moltenvk       fetch_moltenvk
stage $W configure-wine configure_wine
stage $W build-wine     build_wine
stage $W install-wine   install_wine
stage $W bundle-deps    bundle_deps
stage $W dxvk           build_dxvk
stage $W dxmt           install_dxmt
rm -f "$BUILD/.done-$W-verify"
stage $W verify         verify

print
ok "Runtime ready: $OUT ($(du -sh "$OUT" | cut -f1))"
print "  $("$OUT/bin/wine" --version)"
print "  next: maintainer/build-public.sh rosetta-dxmt, then maintainer/package.sh <version>"
