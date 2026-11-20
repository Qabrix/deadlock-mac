#!/bin/zsh
# Put a release together from the built runtimes and maintainer/build-public.sh's pieces:
#   deadlock-mac-<v>.tar.gz        scripts, bin/dl-helper, Deadlock Launcher.app
#   runtime-rosetta-<v>.tar.xz     x86_64 Wine + DXMT + DXVK (Steam's UI) + MoltenVK
#   runtime-arm64-<v>.tar.xz       neutron's tool folder with our Wine pieces, DXMT and FEX
#   SHA256SUMS
#   maintainer/package.sh <version>      -> $DL_ROOT/build/public/release/<version>/
#   maintainer/package.sh <version> --scripts-only   only the scripts tarball again (runtimes stay)
# Inputs (override with env): ROSETTA_SRC (built Rosetta runtime), NEUTRON_SRC (neutron's dist/neutron).
# Nothing from Apple's Game Porting Toolkit goes into a release: players import it themselves (deadlock gptk).
set -euo pipefail
here=${0:A:h} repo=${0:A:h:h}
source "$repo/lib/common.sh"
V=${1:?usage: maintainer/package.sh <version> [--scripts-only]}
SCRIPTS_ONLY=$([[ ${2:-} == --scripts-only ]] && print 1 || print 0)
B=$DL_ROOT/build O=$B/public/out R=$B/public/release/$V ST=$B/public/stage-$V
ROSETTA_SRC=${ROSETTA_SRC:-$DL_ROOT/runtime/wine-winecx-wine1117-e0aa3807}
NEUTRON_SRC=${NEUTRON_SRC:-$B/arm64/work/dist/neutron}
STRIP=$B/arm64/work/toolchains/llvm-mingw-20260908-ucrt-macos-universal/bin/llvm-strip
MIN=15
for d in rosetta-dxmt arm64-dxmt arm64-wine arm64-fex arm64-deps; do
  [[ -d $O/$d ]] || die "missing $O/$d: maintainer/build-public.sh / build-arm64-deps.sh"
done
[[ -z $(git -C "$repo" status --porcelain) ]] || warn "uncommitted changes in $repo go into the release"
if (( SCRIPTS_ONLY )); then rm -rf "$ST"; else rm -rf "$ST" "$R"; fi
mkdir -p "$ST" "$R"

check_macho() {   # check_macho <dir>: every Mach-O targets macOS <= $MIN and carries no entitlements
  local f v n=0
  while IFS= read -r f; do
    file -b "$f" | grep -q Mach-O || continue
    v=$(otool -l "$f" | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print $2; exit} /LC_VERSION_MIN_MACOSX/{g=1} g&&/ version/{print $2; exit}')
    [[ -z $v || ${v%%.*} -le $MIN ]] || die "${f#$1/} targets macOS $v"
    codesign -d --entitlements - "$f" 2>/dev/null | grep -q '\[Key\]' && die "${f#$1/} has entitlements"
    n=$(( n + 1 ))
  done < <(find "$1" -type f \( -perm -u+x -o -name '*.so' -o -name '*.dylib' \))
  ok "${1:t}: $n Mach-O files, all macOS <= $MIN"
}
strip_pe() {   # PE DLLs/EXEs without their DWARF sections (Wine's builtins are built with -g)
  find "$1" -type f \( -name '*.dll' -o -name '*.exe' -o -name '*.drv' -o -name '*.sys' -o -name '*.ocx' -o -name '*.cpl' \
    -o -name '*.acm' -o -name '*.ax' -o -name '*.tlb' -o -name '*.ds' \) -print0 | xargs -0 -n 64 "$STRIP" --strip-debug 2>/dev/null || true
}

# ---------------------------------------------------------------- scripts + launcher
step "scripts and launcher"
S=$ST/deadlock-mac-$V
mkdir -p "$S"
git -C "$repo" ls-files -z | (cd "$repo" && xargs -0 tar -cf - ) | tar -xf - -C "$S"
DL_APP_DIR="$HOME/Library/Application Support/deadlock-mac" "$repo/launcher/make-app.sh" "$S" >/dev/null
cp -p "$repo/bin/dl-helper" "$S/bin/dl-helper"
print -r -- "$V" > "$S/VERSION"
tar -czf "$R/deadlock-mac-$V.tar.gz" -C "$ST" "deadlock-mac-$V"
if (( SCRIPTS_ONLY )); then
  (cd "$R" && shasum -a 256 *.tar.* > SHA256SUMS); rm -rf "$ST"; ok "scripts of $V repackaged"; exit 0
fi

# ---------------------------------------------------------------- Rosetta runtime
step "Rosetta runtime"
S=$ST/rosetta-$V
mkdir -p "$S/lib"
cp -c -R "$ROSETTA_SRC/bin" "$ROSETTA_SRC/share" "$S/"
cp -c -R "$ROSETTA_SRC/lib/wine" "$ROSETTA_SRC/lib/dxvk" "$S/lib/"
cp -c -P "$ROSETTA_SRC"/lib/*.dylib "$S/lib/"
cp -c -R "$O/rosetta-dxmt" "$S/lib/dxmt"
find "$S" \( -name "*.before*" -o -name "*.prev" -o -name "*.bak" -o -name "*.orig" \) -delete
strip_pe "$S/lib/wine"
check_macho "$S"
print -r -- "$V" > "$S/VERSION"
XZ_OPT=-T0 tar -cJf "$R/runtime-rosetta-$V.tar.xz" -C "$ST" "rosetta-$V"

# ---------------------------------------------------------------- ARM64 runtime
step "ARM64 runtime"
S=$ST/arm64-$V F=$S/files
mkdir -p "$S"
for f in compatibilitytool.vdf toolmanifest.vdf neutron neutron.sb peicon.py files; do cp -c -R "$NEUTRON_SRC/$f" "$S/"; done
(cd "$S" && patch -s -p1 < "$repo/patches/arm64/neutron-tool-0001-no-python-prompt.patch")
find "$S" \( -name "*.before*" -o -name "*.prev" -o -name "*.bak" -o -name "*.orig" \) -delete
UL=$F/lib/wine/aarch64-unix PE=$F/lib/wine/aarch64-windows
cp -p "$O/arm64-wine/bin/wineserver" "$F/bin/wineserver"
cp -p "$O"/arm64-wine/aarch64-unix/*.so "$UL/"
cp -p "$O"/arm64-wine/aarch64-windows/*.dll "$PE/"
for f in d3d11 dxgi d3d10core winemetal nvngx; do cp -p "$O/arm64-dxmt/$f.dll" "$PE/"; done
cp -p "$O/arm64-dxmt/winemetal.so" "$UL/"
mkdir -p "$F/lib/deadlock-mac"; cp -p "$O/arm64-dxmt/nvapi64.dll" "$F/lib/deadlock-mac/"
cp -p "$O/arm64-fex/libarm64ecfex.dll" "$PE/"; cp -p "$O/arm64-fex/libarm64ecfex.so" "$UL/"
# gnutls/freetype and their dependencies built for macOS 15 instead of the build machine's Homebrew copies
find "$F/lib" -maxdepth 1 -name '*.dylib' ! -name 'libSDL*' -delete
cp -p "$O"/arm64-deps/*.dylib "$F/lib/"
# DLSS files are put in at play time (Apple's nvngx.dll comes from the player's own toolkit download)
rm -rf "$F/lib/neutron/dlss"; mkdir -p "$F/lib/neutron/dlss"
# Game Mode off (it made no difference in our measurements; some players report audio problems with it)
plutil -replace LSSupportsGameMode -bool false "$UL/Neutron.app/Contents/Info.plist"
# plain ad-hoc signatures for everything we replaced or edited
codesign -f -s - "$UL/Neutron.app/Contents/MacOS/wine" >/dev/null 2>&1
codesign -f -s - "$UL/Neutron.app" >/dev/null 2>&1
for f in "$F/bin/wineserver" "$UL"/*.so; do codesign -f -s - "$f" >/dev/null 2>&1; done
strip_pe "$F/lib/wine"
check_macho "$S"
print -r -- "$V" > "$S/VERSION"
XZ_OPT=-T0 tar -cJf "$R/runtime-arm64-$V.tar.xz" -C "$ST" "arm64-$V"

(cd "$R" && shasum -a 256 *.tar.* > SHA256SUMS)
rm -rf "$ST"
ls -la "$R"
ok "release $V in $R"
