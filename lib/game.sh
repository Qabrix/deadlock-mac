# Game-side settings both paths share (written into the game's files while it is closed). Sourced.

rosetta_cfgs() { print -rl -- "$STEAM_DIR"/userdata/*/$APPID/local/cfg(N/); }
mac_cfgs() { print -rl -- "$MAC_STEAM_USERDATA"/*/$APPID/local/cfg(N/); }

# The game's frame cap (fps_max, an archived convar: the saved machine_convars.vcfg wins). Written before start
# (the game rewrites the file on exit); the first change keeps the original as machine_convars.vcfg.before-fps-max.
# PRESET_FPS_MAX 0 = leave the saved value.
apply_fps_max() {   # apply_fps_max <cfg dir>...
  local want=$PRESET_FPS_MAX mc d
  [[ $want == <1-999> ]] || return 0
  game_running && return 0
  for d in "$@"; do
    mc=$d/machine_convars.vcfg
    [[ -f $mc ]] && grep -q '"fps_max"[[:space:]]' "$mc" || continue
    [[ -f $mc.before-fps-max ]] || cp -f "$mc" "$mc.before-fps-max"
    sed -i '' -E "s/(\"fps_max\"[[:space:]]+)\"[0-9]+\"/\1\"$want\"/" "$mc"
  done
  return 0
}

# DLSS shows the game an NVIDIA GPU; on every switch between that and the real GPU the game resets video.txt
# ("Graphics Device changed"). So the file is swapped while the game is closed: the settings of the last DLSS
# session (video.txt.after-dlss) and of the last session without it (video.txt.after-stretch) are kept apart.
swap_video_settings() {   # swap_video_settings <dlss 0|1> <cfg dir>...
  local dlss=$1 d v; shift
  game_running && return 0
  for d in "$@"; do
    v=$d/video.txt
    [[ -f $v ]] || continue
    if grep -q '"VendorID"[[:space:]]*"4318"' "$v"; then   # 4318 = 0x10DE, NVIDIA
      (( dlss )) && continue
      cp -f "$v" "$v.after-dlss"
      [[ -f $v.after-stretch ]] && cp -f "$v.after-stretch" "$v" && ok "video settings without DLSS restored"
    else
      (( dlss )) || continue
      cp -f "$v" "$v.after-stretch"
      [[ -f $v.after-dlss ]] && cp -f "$v.after-dlss" "$v" && ok "DLSS video settings restored"
    fi
  done
  return 0
}

# Exclusive fullscreen at a resolution other than the desktop's starts cropped (the display mode changes after the
# game's Metal layer is placed). So the Mac switches to the game's resolution first; tools/game-display-mode.sh puts
# the desktop mode back when the game exits (deadlock kill does too). DL_GAME_DISPLAY_MODE=0: off.
DISPLAYMODE_STATE=$DL_ROOT/.desktop-display-mode
restore_desktop_mode() {
  [[ -f $DISPLAYMODE_STATE ]] || return 0
  local mode=$(<$DISPLAYMODE_STATE)
  pkill -f "tools/game-display-mode.sh" 2>/dev/null || true
  [[ $mode == <->x<-> ]] && "$HELPER" displaymode set "$mode" >/dev/null 2>&1 && ok "desktop display mode restored ($mode)"
  rm -f "$DISPLAYMODE_STATE"
}
apply_game_display_mode() {   # apply_game_display_mode <cfg dir>
  [[ ${DL_GAME_DISPLAY_MODE:-1} != 0 && -x $HELPER ]] || return 0
  game_running && return 0
  local v=$1/video.txt w h cur
  [[ -f $v ]] || return 0
  grep -q '"setting\.fullscreen"[[:space:]]*"1"' "$v" && grep -q '"setting\.nowindowborder"[[:space:]]*"0"' "$v" || return 0
  w=$(sed -nE 's/.*"setting\.defaultres"[[:space:]]*"([0-9]+)".*/\1/p' "$v")
  h=$(sed -nE 's/.*"setting\.defaultresheight"[[:space:]]*"([0-9]+)".*/\1/p' "$v")
  [[ $w == <-> && $h == <-> ]] || return 0
  cur=$("$HELPER" displaymode | awk '{print $1}')
  [[ $cur == <->x<-> && $cur != "${w}x${h}" ]] || return 0
  "$HELPER" displaymode list | awk '{print $1}' | grep -qx "${w}x${h}" || return 0
  [[ -f $DISPLAYMODE_STATE ]] || print -r -- "$cur" > "$DISPLAYMODE_STATE"
  "$HELPER" displaymode set "${w}x${h}" >/dev/null 2>&1 || { rm -f "$DISPLAYMODE_STATE"; return 0; }
  pkill -f "tools/game-display-mode.sh" 2>/dev/null || true
  nohup "$DL_APP/tools/game-display-mode.sh" "$HELPER" "$DISPLAYMODE_STATE" </dev/null >/dev/null 2>&1 &!
  ok "display switched to the game's ${w}x${h} (the desktop's $cur comes back when the game exits)"
}

# Custom map, mods, parkour helpers: fills GAME_EXTRA with the game arguments they need.
#   MAP=<name>: start straight into that map (its mod mounted, +sv_cheats 1 unless DL_MAP_CHEATS=0, loaded a second
#     time by Wine's console channel once you are in the map: a custom map's own data, e.g. its hero, is only in
#     use from a second load)
#   MODS=0 | 1 (all stored) | a,b: mounted only for this start, removed otherwise
#   PARKOUR=1: Q checkpoint, E teleport, T stopwatch, H clear (sv_cheats maps)
GAME_EXTRA=()
apply_map_mods() {   # apply_map_mods <game/citadel dir>
  local citadel=$1 mapmod
  if [[ -n ${MAP:-} ]]; then
    mapmod=$("$DL_APP/tools/map-cfg.sh" "$citadel" on "$MAP")
    [[ ${MODS:-0} == 0 && -n $mapmod ]] && MODS=$mapmod
    (( ${DL_MAP_CHEATS:-1} )) && GAME_EXTRA+=(+sv_cheats 1)
    GAME_EXTRA+=(+map "$MAP")
  else
    "$DL_APP/tools/map-cfg.sh" "$citadel" off
  fi
  if [[ ${MODS:-0} != 0 ]]; then "$DL_APP/tools/mods.sh" on "$MODS"; else "$DL_APP/tools/mods.sh" off; fi
  # the console channel: F9 runs cfg/dl_parkour.cfg, which Wine's Mac driver writes
  export WINE_MAC_CONSOLE=$citadel
  if (( ${PARKOUR:-0} )) || [[ -n ${MAP:-} ]]; then
    "$DL_APP/tools/parkour-cfg.sh" "$citadel" on && GAME_EXTRA=(+exec dl_parkour_init $GAME_EXTRA)
  else
    "$DL_APP/tools/parkour-cfg.sh" "$citadel" off
  fi
  if (( ${PARKOUR:-0} )); then export WINE_MAC_PARKOUR=$citadel; else unset WINE_MAC_PARKOUR; fi
}

# Input helpers in Wine's Mac driver (both paths). Mouse-look gets every device report as relative motion; the
# scroll-wheel jump helpers (WHEEL=1) are for Jump bound to both Space and the wheel.
input_env() {
  export WINE_MAC_RELATIVE_LOOK=1 WINE_MAC_NO_COALESCE=1
  if (( ${WHEEL:-0} )); then
    # one wheel flick = one jump; the wheel while Space is held = a fresh Space press; a wheel jump within Jump's
    # 0.15 s cooldown after Space waits for it; after a quick double Space the wheel is raw for wall jumps
    export WINE_MAC_WHEEL_GATE=50 WINE_MAC_WHEEL_REPRESS=49:up:25 WINE_MAC_WHEEL_AFTER_KEY_MS=160 \
           WINE_MAC_WHEEL_RAW_AFTER_PAIR=400:1500
  else
    unset WINE_MAC_WHEEL_GATE WINE_MAC_WHEEL_REPRESS WINE_MAC_WHEEL_AFTER_KEY_MS WINE_MAC_WHEEL_RAW_AFTER_PAIR
  fi
}

# DXMT settings both paths use (measured on the Air; none of them changes the picture)
dxmt_env() {   # dxmt_env <dlss 0|1>
  local L=$DL_LOGS
  mkdir -p "$L"
  export DXMT_ENCODE_PRIORITY=${DXMT_ENCODE_PRIORITY:-high}   # encode threads don't take P-cores from the game
  export DXMT_MERGE_DEPTH=1 DXMT_LOSSLESS=1 DXMT_MV_RG16=1 DXMT_FRAMEBUFFER_ONLY=1 DXMT_FAST_MATH=1 \
         DXMT_TIMESTAMP_LAZY=1 DXMT_TRIM_RENDER_AREA=1 DXMT_LOAD_SKIP=1
  export DXMT_REFLEX_FPS=$PRESET_REFLEX_FPS DXMT_FRAMEGEN_REFRESH=$HW_REFRESH
  if (( ${VSYNC:-0} )); then export DXMT_VSYNC=1; else unset DXMT_VSYNC; fi
  if [[ -n ${FRAMEGEN:-} ]]; then export DXMT_FRAMEGEN=$FRAMEGEN; else unset DXMT_FRAMEGEN; fi
  if (( $1 )); then
    # DLSS runs on MetalFX Temporal; sharpening right after it, before the game's UI
    export DXMT_ENABLE_NVEXT=1 DXMT_NV_FAKE_DRS=1 WINE_DRIVER_VERSION=32.0.15.8108
    print -r -- 1,1 > "$L/dlss-jitter.txt"; print -r -- 0 > "$L/dlss-reactive.txt"
    export DXMT_DLSS_JITTER=1,1 DXMT_DLSS_JITTER_FILE=$(winpath "$L/dlss-jitter.txt") \
           DXMT_DLSS_REACTIVE_FILE=$(winpath "$L/dlss-reactive.txt")
    export DXMT_SHARPEN=${DL_SHARPEN:-0.6}
  else
    unset DXMT_ENABLE_NVEXT DXMT_NV_FAKE_DRS WINE_DRIVER_VERSION DXMT_DLSS_JITTER DXMT_DLSS_JITTER_FILE DXMT_DLSS_REACTIVE_FILE
    export DXMT_SHARPEN=${DL_SHARPEN:-0}
  fi
  print -r -- "$DXMT_SHARPEN" > "$L/sharpen.txt"; export DXMT_SHARPEN_FILE=$(winpath "$L/sharpen.txt")
  print -r -- 0 > "$L/fps-cap.txt"; export DXMT_FPS_CAP_FILE=$(winpath "$L/fps-cap.txt")
  # frame times of the last two sessions, for bug reports about stutter
  [[ -f $L/frame-times.log ]] && mv -f "$L/frame-times.log" "$L/frame-times.prev.log"
  export DXMT_FRAME_TIMES=$(winpath "$L/frame-times.log")
}

# Bluetooth headphones. 1) Deadlock always opens the default mic (voice chat); a headset whose own mic is open drops to
# call quality (mono, 16 kHz): the default mic moves to the built-in one (DL_BT_MIC=1 keeps the headset's). 2) At
# 44.1 kHz the headset's 512-frame callbacks are 11.6 ms, so a 10 ms CoreAudio period leaves no slack and the game
# logs "Audio device starved": 30 ms there (DL_BT_AUDIO_MS; DL_AUDIO_MS wins). Bluetooth adds ~150-200 ms anyway.
# Sets AUDIO_PERIOD_MS (and prints when it changes something).
bt_audio_env() {
  AUDIO_PERIOD_MS=${DL_AUDIO_MS:-10}
  [[ -x $HELPER ]] || return 0
  (( ${DL_BT_MIC:-0} )) || "$HELPER" audio-bt-guard
  if [[ -z ${DL_AUDIO_MS:-} && $("$HELPER" audio-output 2>/dev/null) == bluetooth ]]; then
    AUDIO_PERIOD_MS=${DL_BT_AUDIO_MS:-30}
    ok "Bluetooth headphones: audio period $AUDIO_PERIOD_MS ms"
  fi
}
