# Pins and paths for the maintainer builds (build-wine.sh, build-llvm15.sh). Sourced, not executed.
source "${${(%):-%x}:A:h:h}/lib/common.sh"

# Wine for the Rosetta path: dappermint/winecx, CrossOver 26.3's macOS changes (msync among them) on upstream Wine
# 11.17, plus patches/wine-rosetta. The CrossOver source drop supplies the gnutls/freetype sources.
DL_WINE=winecx
CX_VERSION="${CX_VERSION:-26.3.0}"
WINECX_REPO=https://github.com/dappermint/winecx.git
WINECX_BRANCH="${WINECX_BRANCH:-wine1117}"
WINECX_COMMIT="${WINECX_COMMIT:-e0aa380780b73e20fabcfe78fd42713b94929a53}"
WINE_ID="winecx-$WINECX_BRANCH-${WINECX_COMMIT[1,8]}"
DL_RUNTIME="$DL_ROOT/runtime"
WINE_HOME="${DL_WINE_HOME:-$DL_RUNTIME/wine-$WINE_ID}"
