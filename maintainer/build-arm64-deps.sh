#!/bin/zsh
# The libraries the ARM64 runtime loads by name (Wine dlopens libgnutls.30.dylib and libfreetype.6.dylib, found
# through neutron's DYLD_FALLBACK_LIBRARY_PATH = files/lib), built for arm64 macOS 15. neutron's own build copies
# them from the build machine's Homebrew, which targets that machine's macOS. Same sources and options as the Rosetta
# runtime (maintainer/build-wine.sh: the CrossOver 26.3 source drop, nettle from its upstream release): gnutls with
# its included libtasn1/libunistring and no p11-kit/idn, so only gmp and nettle come along.
#   maintainer/build-arm64-deps.sh      -> $DL_ROOT/build/public/out/arm64-deps/*.dylib
set -euo pipefail
source "${0:A:h}/build-env.sh"
B=$DL_ROOT/build P=$B/public SRC=$P/deps-src OBJ=$P/deps-obj DEPS=$P/deps-install OUT=$P/out/arm64-deps
export MACOSX_DEPLOYMENT_TARGET=15.0 CC="clang -arch arm64" CXX="clang++ -arch arm64"
export PKG_CONFIG_PATH=$DEPS/lib/pkgconfig PKG_CONFIG_LIBDIR=$DEPS/lib/pkgconfig   # never Homebrew's
export CPPFLAGS="-I$DEPS/include" LDFLAGS="-L$DEPS/lib -Wl,-headerpad_max_install_names"
host=(--build=aarch64-apple-darwin --host=aarch64-apple-darwin)
JOBS=$(sysctl -n hw.ncpu)
game_running && die "Deadlock is running: build later"

if [[ ! -d $SRC/gnutls ]]; then
  mkdir -p "$SRC"
  tar -xzf "$B/crossover-sources-$CX_VERSION.tar.gz" -C "$SRC" --strip-components 1 sources/gnutls sources/freetype
fi
NETTLE=$B/nettle-3.10
[[ -f $NETTLE/configure ]] || die "missing $NETTLE (maintainer/build-wine.sh fetches it)"
mkdir -p "$OBJ" "$DEPS"

[[ -f $DEPS/lib/libgmp.10.dylib ]] || {
  mkdir -p "$OBJ/gmp" && cd "$OBJ/gmp"
  "$SRC/gnutls/gmp/configure" --prefix="$DEPS" $host --enable-shared --disable-static --disable-assembly
  make -j$JOBS && make install
}
[[ -f $DEPS/lib/libhogweed.dylib ]] || {
  mkdir -p "$OBJ/nettle" && cd "$OBJ/nettle"
  "$NETTLE/configure" --prefix="$DEPS" --libdir="$DEPS/lib" $host --enable-shared --disable-static \
    --disable-openssl --disable-documentation
  make -j$JOBS && make install
}
[[ -f $DEPS/lib/libgnutls.30.dylib ]] || {
  rm -rf "$OBJ/gnutls" && mkdir -p "$OBJ/gnutls" && cd "$OBJ/gnutls"
  LIBS=-lnettle "$SRC/gnutls/gnutls/configure" --prefix="$DEPS" $host --enable-shared --disable-static \
    --with-included-libtasn1 --with-included-unistring \
    --without-p11-kit --without-idn --without-zstd --without-brotli --without-tpm --without-tpm2 \
    --disable-doc --disable-tests --disable-tools --disable-cxx --disable-nls \
    --disable-libdane --disable-guile --disable-full-test-suite
  make -j$JOBS && make install
}
[[ -f $DEPS/lib/libfreetype.6.dylib ]] || {
  cmake -S "$SRC/freetype" -B "$OBJ/freetype" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$DEPS" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET \
    -DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew -DBUILD_SHARED_LIBS=ON -DCMAKE_INSTALL_NAME_DIR="$DEPS/lib" \
    -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_BROTLI=ON -DFT_DISABLE_PNG=ON -DFT_REQUIRE_ZLIB=ON -DFT_REQUIRE_BZIP2=ON
  cmake --build "$OBJ/freetype" -j$JOBS && cmake --install "$OBJ/freetype"
}

# self-contained: each library finds its dependencies next to itself
rm -rf "$OUT"; mkdir -p "$OUT"
libs=(libgmp.10.dylib libnettle.8.dylib libhogweed.6.dylib libgnutls.30.dylib libfreetype.6.dylib)
for l in $libs; do cp -L "$DEPS/lib/$l" "$OUT/$l"; chmod u+w "$OUT/$l"; done
for l in $libs; do
  install_name_tool -id "@loader_path/$l" "$OUT/$l"
  for dep in $(otool -L "$OUT/$l" | awk -v d="$DEPS/lib/" 'NR > 1 && index($1, d) == 1 {print $1}'); do
    install_name_tool -change "$dep" "@loader_path/${dep:t}" "$OUT/$l"
  done
  codesign -f -s - "$OUT/$l" >/dev/null 2>&1
done
otool -L "$OUT"/*.dylib | grep -E '/opt/homebrew|/usr/local|'"$DEPS" && die "a library still points outside the runtime"
ok "ARM64 libraries -> $OUT: $(ls "$OUT" | tr '\n' ' ')"
