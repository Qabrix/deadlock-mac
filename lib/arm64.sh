# The ARM64 path: arm64 Wine with ARM64EC system DLLs, FEX for the game's x86_64 code and DXMT as ARM64EC, built
# from neutron (github.com/lixsldotnet/neutron) plus our patches. No Rosetta for Wine or Direct3D. The game files are
# the ones Windows Steam of the Rosetta path installed and updates; the game talks to Mac Steam (it must be running
# and logged in) through Proton's lsteamclient. Steam.app is not modified. Sourced by bin/deadlock.

ARM64_DIST=$ARM64_HOME
ARM64_COMPAT=$DL_ROOT/arm64/compatdata/$APPID

arm64_kill() {
  [[ -x $ARM64_DIST/files/bin/wineserver ]] && WINEPREFIX="$ARM64_COMPAT/pfx" "$ARM64_DIST/files/bin/wineserver" -k 2>/dev/null || true
  ok "ARM64 session stopped"
}

arm64_play() {
  [[ -x $ARM64_DIST/neutron ]] || die "ARM64 runtime missing ($ARM64_DIST): run the installer with the ARM64 runtime"
  pgrep -xq steam_osx || die "start Mac Steam (/Applications/Steam.app) and log in first"
  local exe="$GAME_DIR/game/bin/win64/deadlock.exe"
  [[ -f $exe ]] || die "Deadlock not downloaded yet: deadlock install (Windows Steam downloads it)"
  game_running && die "Deadlock is already running"
  # the Rosetta path's Windows Steam isn't needed (~0.6 core)
  if pgrep -f 'Steam\\steam.exe|Steam/steam.exe' >/dev/null; then rosetta_kill >/dev/null; fi
  # new game build? only Windows Steam can fetch it (DL_UPDATE=0: skip)
  if [[ ${DL_UPDATE:-1} != 0 ]]; then
    rosetta_update || warn "game update failed: starting the installed build (online play needs the newest)"
  fi
  hw_preset
  mkdir -p "$ARM64_COMPAT" "$DL_LOGS"
  local pe="$ARM64_DIST/files/lib/wine/aarch64-windows" dlss=0
  # DLSS: Apple's signed nvngx.dll in system32 for the game's signature check, DXMT's own (MetalFX) loaded instead
  if (( ${DLSS:-1} )) && gptk_ok; then
    dlss=1
    local dlssdir="$ARM64_DIST/files/lib/neutron/dlss"
    mkdir -p "$dlssdir"
    cmp -s "$GPTK_DIR/nvngx.dll" "$dlssdir/nvngx.dll" || cp -p "$GPTK_DIR/nvngx.dll" "$dlssdir/nvngx.dll"
    # DXMT's nvapi64 (Reflex) is kept outside Wine's DLL folder: neutron copies this folder into system32
    local nvapi="$ARM64_DIST/files/lib/deadlock-mac/nvapi64.dll"
    cmp -s "$nvapi" "$dlssdir/nvapi64.dll" || cp -p "$nvapi" "$dlssdir/nvapi64.dll"
    export NEUTRON_DLSS=1 D3DM_VENDOR_ID=0x10DE
    export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+$WINEDLLOVERRIDES;}nvngx=b"
  else
    export NEUTRON_DLSS=0; unset D3DM_VENDOR_ID
  fi
  dxmt_env $dlss
  input_env
  swap_video_settings $dlss $(mac_cfgs)
  # the same video settings as the Rosetta path (Mac Steam keeps its own cfg folder; its copy is kept once)
  local r=(${(f)"$(rosetta_cfgs)"}) m
  if [[ -n ${r[1]:-} && -f ${r[1]}/video.txt ]]; then
    for m in ${(f)"$(mac_cfgs)"}; do
      [[ ! -f $m/video.txt.before-parity && -f $m/video.txt ]] && ! cmp -s "$m/video.txt" "${r[1]}/video.txt" &&
        cp -p "$m/video.txt" "$m/video.txt.before-parity"
      cp -p "${r[1]}/video.txt" "$m/video.txt"
    done
  fi
  apply_fps_max $(mac_cfgs)
  apply_map_mods "$CITADEL"
  "$DL_APP/tools/sync-game-cfg.sh"
  export STEAM_COMPAT_DATA_PATH=$ARM64_COMPAT STEAM_COMPAT_INSTALL_PATH=$GAME_DIR
  export SteamAppId=$APPID SteamGameId=$APPID STEAM_COMPAT_APP_ID=$APPID
  if (( ${HUD:-0} )); then export NEUTRON_HUD=1; else export NEUTRON_HUD=0; fi
  # no whole-display MetalFX rescale (the game's own upscaler / DLSS does that), msync without spinning
  export NEUTRON_RENDER_SCALE=1 NEUTRON_MSYNC=1 NEUTRON_MSYNC_SPIN=0
  export WINE_MAINTHRD_QOS=1 WINE_SERVER_QOS=1
  bt_audio_env
  export WINE_COREAUDIO_MIN_PERIOD_MS=$AUDIO_PERIOD_MS
  if [[ ${DL_MIX_RATE:-44100} != 0 ]]; then export WINE_COREAUDIO_MIX_RATE=${DL_MIX_RATE:-44100}; else unset WINE_COREAUDIO_MIX_RATE; fi
  # FEX: x86 memory order where Source 2's lock-free code needs it (our FEX patches), AVX hidden like on Rosetta
  export FEX_VECTORTSOENABLED=0 FEX_VOLATILEMETADATA=1 FEX_HOSTFEATURES=disableavx FEX_HARDWARE_TSO=0
  if (( ${DL_FEX_SAFE:-0} )); then export FEX_MULTIBLOCK=0 FEX_SMCCHECKS=full NEUTRON_FEX_TSO=strict; fi
  # FEX's block cache: code translated in earlier sessions loads instead of being compiled again (fewer hitches).
  # One folder per FEX build, the three newest kept, a new one past 3.5 GiB.
  local fexroot="$ARM64_COMPAT/pfx/drive_c/users/steamuser/AppData/Local/fex-emu" fexid cache old d
  fexid=$(stat -f %m-%z "$pe/libarm64ecfex.dll")
  cache="$fexroot/DiskCache-$fexid"
  [[ -d $cache ]] && (( $(du -sk "$cache" | cut -f1) > 3670016 )) && rm -rf "${cache:?}"
  mkdir -p "$cache"; touch "$cache"
  old=("$fexroot"/DiskCache-*(N/om)); for d in ${old[4,-1]}; do rm -rf -- "$d"; done
  export FEX_DISKCACHE=1 FEX_DISKCACHEMAXFILESIZE=4294967296 FEX_DISKCACHEPATH="C:/users/steamuser/AppData/Local/fex-emu/DiskCache-$fexid/"
  [[ -z $(ls -A "$cache") ]] && warn "FEX's code cache is empty: the first ~15 minutes can hitch while it fills"
  local lang=()
  [[ -n ${DL_LANGUAGE:-} ]] && lang=(-language $DL_LANGUAGE)
  ok "Deadlock on ARM64 (FEX + DXMT, DLSS: $dlss, tier: $HW_TIER, ${HW_REFRESH} Hz); log: ~/Library/Logs/neutron/neutron-$APPID.log"
  # detached: closing Terminal doesn't end the game
  nohup "$ARM64_DIST/neutron" run "$exe" $DEADLOCK_ARGS -nojoy $lang $GAME_EXTRA $EXTRA_ARGS </dev/null >/dev/null 2>&1 &!
  ok "started"
}
