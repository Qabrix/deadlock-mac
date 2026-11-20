#!/bin/zsh
# deadlock-mac installer: downloads the newest release (scripts, launcher, runtimes), then sets up Windows Steam.
#   curl -fsSL https://raw.githubusercontent.com/Qabrix/deadlock-mac/main/install.sh | zsh
#   zsh install.sh [--no-arm64] [--version <tag>] [--no-setup] [--from <release folder>]
#   (--from: install a locally built release, e.g. $DL_ROOT/build/public/release/<tag>, without GitHub)
# Re-running it updates to the newest release; your Steam login, game files and settings stay.
# Files downloaded with curl are not quarantined, so macOS opens the launcher without the unidentified-developer
# prompt. Everything goes to:
#   ~/Library/Application Support/deadlock-mac   scripts, helper (the `deadlock` command: bin/deadlock)
#   ~/Applications/Deadlock Launcher.app
#   ~/Games/Deadlock.noindex                     runtimes, Wine prefix with Steam and the game (DL_ROOT)
set -euo pipefail
REPO=${DL_REPO:-Qabrix/deadlock-mac}
APP_DIR=${DL_APP_DIR:-"$HOME/Library/Application Support/deadlock-mac"}
LAUNCHER_DIR=${DL_LAUNCHER_DIR:-$HOME/Applications}
DL_ROOT=${DL_ROOT:-$HOME/Games/Deadlock.noindex}
ARM64=1 VERSION= SETUP=1 FROM= OPEN=1
while (( $# )); do
  case $1 in
    --no-arm64) ARM64=0 ;;
    --version) VERSION=$2; shift ;;
    --no-setup) SETUP=0 ;;
    --no-open) OPEN=0 ;;
    --from) FROM=${2:A}; shift ;;
    *) print -u2 "unknown option: $1"; exit 2 ;;
  esac
  shift
done

die()  { print -u2 -- "✗ $*"; exit 1; }
step() { print -- "▶ $*"; }
ok()   { print -- "✓ $*"; }

# ---------------------------------------------------------------- checks
[[ $(uname -m) == arm64 ]] || die "deadlock-mac needs a Mac with Apple silicon (M1 or newer)"
macos=$(sw_vers -productVersion)
(( ${macos%%.*} >= 15 )) || die "macOS 15 or newer needed (this Mac: $macos)"
if [[ ! -e /Library/Apple/usr/libexec/oah/libRosettaRuntime ]]; then
  step "Installing Rosetta 2 (Apple's x86 translator; macOS may ask for your password)"
  softwareupdate --install-rosetta --agree-to-license || die "Rosetta 2 install failed"
fi
mkdir -p "$DL_ROOT/cache/downloads" "$DL_ROOT/runtime"
free_gb=$(( $(df -k "$DL_ROOT" | awk 'NR==2{print $4}') / 1024 / 1024 ))
(( free_gb >= 55 )) || print -u2 "! only $free_gb GB free on that disk: the game, runtimes and shader caches need ~55 GB"
pgrep -qf '^[A-Za-z]:\\.*\\deadlock\.exe' && die "Deadlock is running: quit it first"

# ---------------------------------------------------------------- release
if [[ -n $FROM ]]; then
  [[ -f $FROM/SHA256SUMS ]] || die "no SHA256SUMS in $FROM"
  VERSION=${VERSION:-$(ls "$FROM" | sed -nE "s/^deadlock-mac-(.*)\.tar\.gz\$/\1/p" | head -1)}
elif [[ -z $VERSION ]]; then
  VERSION=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | plutil -extract tag_name raw -o - - 2>/dev/null) ||
    die "could not find the newest release of $REPO"
fi
base="https://github.com/$REPO/releases/download/$VERSION"
[[ -n $FROM ]] && base="file://$FROM"
dl="$DL_ROOT/cache/downloads/$VERSION"
mkdir -p "$dl"
step "deadlock-mac $VERSION"
curl -fsSL -o "$dl/SHA256SUMS" "$base/SHA256SUMS" || die "download failed: $base/SHA256SUMS"
fetch() {   # fetch <asset>: download (resumes) and verify
  local f=$1 want
  want=$(awk -v f="$f" '$2 == f || $2 == "*"f { print $1 }' "$dl/SHA256SUMS")
  [[ -n $want ]] || die "$f is not part of release $VERSION"
  if [[ -f $dl/$f && $(shasum -a 256 "$dl/$f" | cut -d' ' -f1) == $want ]]; then return 0; fi
  step "downloading $f"
  curl -fL --progress-bar -C - -o "$dl/$f" "$base/$f" || curl -fL --progress-bar -o "$dl/$f" "$base/$f" || die "download failed: $f"
  [[ $(shasum -a 256 "$dl/$f" | cut -d' ' -f1) == $want ]] || { rm -f "$dl/$f"; die "$f: checksum mismatch, try again"; }
}

# ---------------------------------------------------------------- scripts + launcher
fetch "deadlock-mac-$VERSION.tar.gz"
rm -rf "$APP_DIR.new"; mkdir -p "$APP_DIR.new"
tar -xzf "$dl/deadlock-mac-$VERSION.tar.gz" -C "$APP_DIR.new" --strip-components 1
rm -rf "$APP_DIR"; mv "$APP_DIR.new" "$APP_DIR"
# where the data lives, for the launcher and the deadlock command (lib/common.sh reads it)
print -r -- "DL_ROOT=${(q)DL_ROOT}" > "$APP_DIR/config.sh"
LAUNCHER="$LAUNCHER_DIR/Deadlock Launcher.app"
mkdir -p "$LAUNCHER_DIR"
rm -rf "$LAUNCHER"
mv "$APP_DIR/Deadlock Launcher.app" "$LAUNCHER"
plutil -replace DLApp -string "$APP_DIR" "$LAUNCHER/Contents/Info.plist"
codesign -f -s - "$LAUNCHER" >/dev/null 2>&1 || true
ok "launcher: $LAUNCHER, command: $APP_DIR/bin/deadlock"

# ---------------------------------------------------------------- runtimes
install_runtime() {   # install_runtime rosetta|arm64
  local kind=$1 f="runtime-$1-$VERSION.tar.xz" dst="$DL_ROOT/runtime/$1-$VERSION" old
  if [[ ! -d $dst ]]; then
    fetch "$f"
    step "unpacking the $kind runtime"
    rm -rf "$dst.tmp"; mkdir -p "$dst.tmp"
    tar -xJf "$dl/$f" -C "$dst.tmp" --strip-components 1
    mv "$dst.tmp" "$dst"
  fi
  ln -sfn "$kind-$VERSION" "$DL_ROOT/runtime/$kind"
  for old in "$DL_ROOT"/runtime/$kind-*(N/); do [[ $old == $dst ]] || rm -rf "$old"; done
  ok "$kind runtime $VERSION"
}
install_runtime rosetta
(( ARM64 )) && install_runtime arm64
# keep only this release's small files (the runtimes are unpacked)
for old in "$DL_ROOT"/cache/downloads/*(N/); do [[ ${old:t} == $VERSION ]] || rm -rf "$old"; done
rm -f "$dl"/runtime-*.tar.xz

# ---------------------------------------------------------------- Windows Steam
if (( SETUP )); then
  "$APP_DIR/bin/deadlock" setup
fi
ok "done. Open Deadlock Launcher to log in to Steam and download the game."
if (( OPEN )); then open "$LAUNCHER" 2>/dev/null || true; fi
