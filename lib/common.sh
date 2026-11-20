# Shared settings for bin/deadlock and tools/*. Sourced, not executed.
# Override any of these from the environment, e.g. DL_ROOT=/Volumes/Games/Deadlock.noindex deadlock setup

DL_APP=${DL_APP:-${${(%):-%x}:A:h:h}}               # this checkout / install (scripts, helper, launcher)
# the installer records the data location here (a DL_ROOT set in the environment wins)
[[ -z ${DL_ROOT:-} && -f $DL_APP/config.sh ]] && source "$DL_APP/config.sh"
# Everything else lives under one root. The ".noindex" suffix keeps Spotlight out of the prefix,
# the ~40 GB of game files and the shader caches.
DL_ROOT=${DL_ROOT:-$HOME/Games/Deadlock.noindex}
DL_PREFIX=${DL_PREFIX:-$DL_ROOT/prefix}             # Wine prefix of the Rosetta path: Windows Steam + the game
DL_CACHE=$DL_ROOT/cache
DL_LOGS=$DL_ROOT/logs
ROSETTA_HOME=${DL_ROSETTA_RUNTIME:-$DL_ROOT/runtime/rosetta}   # x86_64 Wine + DXMT + DXVK (for Steam's UI)
ARM64_HOME=${DL_ARM64_RUNTIME:-$DL_ROOT/runtime/arm64}         # arm64 Wine + FEX + DXMT (a neutron tool folder)
GPTK_DIR=$DL_ROOT/gptk                               # Apple's signed nvngx.dll for DLSS (deadlock gptk <dmg>)
HELPER=$DL_APP/bin/dl-helper

STEAM_DIR="$DL_PREFIX/drive_c/Program Files (x86)/Steam"
STEAM_EXE="$STEAM_DIR/steam.exe"
GAME_DIR="$STEAM_DIR/steamapps/common/Deadlock"
CITADEL="$GAME_DIR/game/citadel"
MAC_STEAM_USERDATA="$HOME/Library/Application Support/Steam/userdata"
APPID=1422450
STEAM_SETUP_URL="https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe"
# -dx11: the Vulkan renderer would go through MoltenVK; DX11 goes through DXMT (Direct3D 11 on Metal).
# -condebug: the console goes to game/citadel/console.log (bug reports).
if [[ -n ${DEADLOCK_ARGS:-} ]]; then DEADLOCK_ARGS=(${=DEADLOCK_ARGS}); else DEADLOCK_ARGS=(-dx11 -novid -condebug); fi
# Steam's own windows (CEF) render through an app-local DXVK; -silent: no window until needed
if [[ -n ${STEAM_ARGS:-} ]]; then STEAM_ARGS=(${=STEAM_ARGS}); else STEAM_ARGS=(-silent -nofriendsui); fi

die()  { print -u2 -- "✗ $*"; exit 1; }
step() { print -- "▶ $*"; }
ok()   { print -- "✓ $*"; }
warn() { print -u2 -- "! $*"; }

game_running() { pgrep -qf '^[A-Za-z]:\\.*\\deadlock\.exe'; }
rosetta_ok() { [[ -e /Library/Apple/usr/libexec/oah/libRosettaRuntime ]]; }
gptk_ok() { [[ -f $GPTK_DIR/nvngx.dll ]]; }
# Wine paths as the game sees them (Z: is /)
winpath() { print -r -- "Z:${1//\//\\}"; }
