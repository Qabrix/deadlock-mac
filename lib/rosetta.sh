# The Rosetta path: Windows Steam and the game in one Wine prefix, x86_64 Wine under Rosetta, Direct3D 11 through
# our DXMT. Sourced by bin/deadlock.

WINE=$ROSETTA_HOME/bin/wine
WINESERVER=$ROSETTA_HOME/bin/wineserver

wine_env() {
  [[ -x $WINE ]] || die "Rosetta runtime missing ($ROSETTA_HOME): run the installer again"
  rosetta_ok || die "Rosetta 2 missing: softwareupdate --install-rosetta --agree-to-license"
  export WINEPREFIX=$DL_PREFIX
  export WINEDEBUG=${WINEDEBUG:--all}
  # msync: Wine's sync objects on Mach semaphores instead of round trips to the wineserver
  export WINEMSYNC=1 WINEESYNC=0
  export WINEDLLOVERRIDES=${WINEDLLOVERRIDES:-mscoree,mshtml=}
  # audio: CoreAudio periods of at least 10 ms (shorter ones crackle under load; 30 ms on Bluetooth: bt_audio_env),
  # and the game mixes at 44.1 kHz (the native rate of its sounds) whatever the output device runs at; DL_MIX_RATE=0 =
  # the device's rate
  bt_audio_env
  export WINE_COREAUDIO_MIN_PERIOD_MS=$AUDIO_PERIOD_MS
  if [[ ${DL_MIX_RATE:-44100} != 0 ]]; then export WINE_COREAUDIO_MIX_RATE=${DL_MIX_RATE:-44100}; else unset WINE_COREAUDIO_MIX_RATE; fi
  mkdir -p "$DL_LOGS"
}

# Steam's web UI (CEF) needs a working D3D11: an app-local DXVK next to Wine's own dxgi (the prefix registry says
# d3d11/d3d10core=native,builtin for steamwebhelper). Steam updates can remove it, so this runs before every start.
steam_ui_dxvk() {
  local cef="$STEAM_DIR/bin/cef/cef.win64" src="$ROSETTA_HOME/lib/dxvk/x86_64-windows" f
  [[ -d $cef && -f $src/d3d11.dll ]] || return 1
  for f in d3d11.dll d3d10core.dll; do cmp -s "$src/$f" "$cef/$f" || cp -f "$src/$f" "$cef/$f"; done
  return 0
}

run_bg() {   # run_bg <log name> <wine args...>: detached; DL_LOG=1 keeps Wine's output in logs/
  steam_ui_dxvk || true
  local name=$1; shift
  if (( ${DL_LOG:-0} )); then
    export WINEDEBUG=${DL_WINEDEBUG:-fixme-all,err+all}
    { nohup "$WINE" "$@" 2>&1 | head -c 100000000 > "$DL_LOGS/$name-$(date +%Y%m%d-%H%M%S).log" } </dev/null >/dev/null 2>&1 &!
  else
    nohup "$WINE" "$@" </dev/null >/dev/null 2>&1 &!
  fi
}

steam_running() { pgrep -qf "${DL_PREFIX:t}/.*[Ss]team.exe|C:.*\\\\Steam\\\\steam.exe"; }
stop_prefix() { "$WINESERVER" -k 2>/dev/null || true; "$WINESERVER" -w 2>/dev/null || true; }

# First start: Steam downloads its client and opens its UI before steam_ui_dxvk can help, so that window would be
# black. Let the update finish, stop Steam, place DXVK.
first_run_update() {
  [[ -f $STEAM_DIR/bin/cef/cef.win64/steamwebhelper.exe ]] && return 0
  step "First Steam start: downloading the Steam client update"
  run_bg steam-update "$STEAM_EXE" -nofriendsui
  integer i
  for (( i = 0; i < 300; i++ )); do [[ -f $STEAM_DIR/bin/cef/cef.win64/steamwebhelper.exe ]] && break; sleep 2; done
  [[ -f $STEAM_DIR/bin/cef/cef.win64/steamwebhelper.exe ]] || die "Steam client update did not finish in 10 min"
  sleep 15
  stop_prefix
  steam_ui_dxvk || die "could not place DXVK for Steam's UI"
  ok "Steam client updated"
}

# The game's environment. Steam hands -applaunch to an already running Steam and the game inherits *that* Steam's
# environment, so every Steam start records it and play restarts Steam when it differs.
SIG_FILE=$DL_ROOT/.steam-game-env
game_env() {
  local dlss=$1
  wine_env
  hw_preset
  [[ -d $ROSETTA_HOME/lib/dxmt/x86_64-windows ]] || die "DXMT missing from $ROSETTA_HOME"
  # DXMT for deadlock.exe only (our ntdll's per-program DLL folders); Steam keeps Wine's own d3d
  export WINE_EXE_DLLPATH="deadlock.exe=$ROSETTA_HOME/lib/dxmt"
  dxmt_env $dlss
  # DLSS: the game loads C:\windows\system32\nvngx.dll (Apple's signed copy, for its signature check); builtin
  # first gives it DXMT's nvngx (MetalFX) instead
  (( dlss )) && export WINEDLLOVERRIDES="$WINEDLLOVERRIDES;nvngx=b"
  # Steam overlay off: it hooks Present and input on the game's main thread
  (( ${OVERLAY:-0} )) || export WINEDLLOVERRIDES="$WINEDLLOVERRIDES;gameoverlayrenderer64,gameoverlayrenderer="
  # AVX hidden (Rosetta runs it on 128-bit NEON; the game's SSE paths are at least as fast)
  unset ROSETTA_ADVERTISE_AVX
  # our Wine: the game's main thread at the top non-realtime QoS tier, the wineserver's request loop at raised
  # precedence, events that skip a server round trip on their first wait
  export WINE_MAINTHRD_QOS=1 WINE_SERVER_QOS=1 WINE_EVENT_PREFILL=1
  input_env
  if (( ${HUD:-0} )); then export MTL_HUD_ENABLED=1; else unset MTL_HUD_ENABLED; fi
  SIG="v1 dlss=$dlss vsync=${VSYNC:-0} framegen=${FRAMEGEN:-} overlay=${OVERLAY:-0} hud=${HUD:-0} wheel=${WHEEL:-0} parkour=${PARKOUR:-0} reflex=$PRESET_REFLEX_FPS refresh=$HW_REFRESH sharpen=$DXMT_SHARPEN steamgpu=${STEAMGPU:-0} audio=$WINE_COREAUDIO_MIN_PERIOD_MS log=${DL_LOG:-0} runtime=${ROSETTA_HOME:A}"
}

start_steam() {   # start_steam <log name> <args...>
  print -r -- "$SIG" > "$SIG_FILE"
  run_bg "$@"
}

rosetta_play() {
  local dlss=0
  (( ${DLSS:-1} )) && gptk_ok && dlss=1
  (( ${DLSS:-1} && !dlss )) && [[ -n ${DLSS_ASKED:-} ]] && warn "DLSS needs Apple's nvngx.dll: deadlock gptk <GPTK dmg>"
  [[ -f $STEAM_EXE ]] || die "Windows Steam not installed yet: deadlock setup"
  [[ -f $GAME_DIR/game/bin/win64/deadlock.exe ]] || die "Deadlock not downloaded yet: deadlock install"
  game_env $dlss
  first_run_update
  swap_video_settings $dlss $(rosetta_cfgs)
  apply_fps_max $(rosetta_cfgs)
  if steam_running && [[ $(<$SIG_FILE 2>/dev/null) != "$SIG" ]]; then
    warn "Steam is running with other game settings: restarting it"
    stop_prefix
  fi
  # Steam's CEF GPU process spins ~0.8 core on Rosetta during matches while drawing nothing: off unless Steam's
  # window or overlay is wanted (its window is then black, but the game runs)
  local args=($STEAM_ARGS)
  (( ${STEAMGPU:-0} || ${OVERLAY:-0} )) || args+=(-cef-disable-gpu -cef-disable-gpu-compositing)
  apply_map_mods "$CITADEL"
  [[ -d $MAC_STEAM_USERDATA ]] && "$DL_APP/tools/sync-game-cfg.sh"
  apply_game_display_mode "$(rosetta_cfgs | head -1)"
  # A Steam that already runs gets the launch handed over and logs ExecCommandLine within seconds. One left running
  # across a sleep or network change can stop taking launches: then it is restarted.
  local con="$STEAM_DIR/logs/console_log.txt" con0 launched i
  con0=$( steam_running && [[ -f $con ]] && wc -l < "$con" || print -- -1 )
  launched=$(date '+%Y-%m-%d %H:%M:%S')
  start_steam deadlock "$STEAM_EXE" $args -applaunch $APPID $DEADLOCK_ARGS $GAME_EXTRA $EXTRA_ARGS
  if (( con0 >= 0 )); then
    for i in {1..10}; do
      tail -n +$(( con0 + 1 )) "$con" 2>/dev/null | grep -aq 'ExecCommandLine:.*-applaunch' && break
      sleep 2
    done
    if ! tail -n +$(( con0 + 1 )) "$con" 2>/dev/null | grep -aq 'ExecCommandLine:.*-applaunch'; then
      warn "the running Steam ignored the launch: restarting Steam"
      stop_prefix
      start_steam deadlock "$STEAM_EXE" $args -applaunch $APPID $DEADLOCK_ARGS $GAME_EXTRA $EXTRA_ARGS
    fi
  fi
  # Windows Steam stays running so the next launch is quick, but idle under Wine it keeps ~1.5 cores busy: stopped
  # ~2 min after the game exits (DL_STEAM_IDLE_STOP=0 keeps it running, another number = seconds to wait)
  pkill -f "tools/steam-idle-stop.sh" 2>/dev/null || true
  if [[ ${DL_STEAM_IDLE_STOP:-120} != 0 ]]; then
    nohup "$DL_APP/tools/steam-idle-stop.sh" "$WINE" "$WINESERVER" "$DL_PREFIX" ${DL_STEAM_IDLE_STOP:-120} \
      </dev/null >/dev/null 2>&1 &!
  fi
  ok "Deadlock launching (Rosetta, DXMT, DLSS: $dlss, tier: $HW_TIER, ${HW_REFRESH} Hz)"
  # Windows Steam can stop a launch on a dialog its black window doesn't show (a failed cloud sync, "Play anyway?"
  # when Valve still sees an old session): wait up to 2 min for the game and name the dialog
  local cl="$STEAM_DIR/logs/cloud_log.txt" cl0 dialog
  cl0=$( [[ -f $cl ]] && wc -l < "$cl" || print 0 )
  for i in {1..60}; do
    game_running && { ok "game started"; return 0; }
    if [[ -f $cl ]] && tail -n +$(( cl0 + 1 )) "$cl" | grep -a "\[AppID $APPID\]" | grep -qi 'failed\|conflict'; then
      warn "Steam Cloud sync failed: Steam waits on a dialog. Start again with \"Show Steam's window\" (--steam-window) and answer it"
      return 1
    fi
    dialog=$( [[ -f $con ]] && awk -v t="[$launched]" 'substr($0, 1, 21) >= t' "$con" |
              grep -a "AppID $APPID.*LaunchApp waiting for user response to" | grep -v ShowInterstitials | tail -1 |
              sed 's/.*waiting for user response to //' )
    if [[ -n $dialog ]]; then
      warn "Steam waits on a dialog ($dialog). Kill, then start with \"Show Steam's window\" (--steam-window) and answer it (e.g. Play anyway)"
      return 1
    fi
    sleep 2
  done
  warn "the game hasn't started after 2 min: kill, then start with \"Show Steam's window\" (--steam-window) to see Steam"
  return 1
}

rosetta_kill() {
  [[ -x $WINESERVER ]] && WINEPREFIX=$DL_PREFIX "$WINESERVER" -k 2>/dev/null || true
  ok "Rosetta session stopped"
}

# Steam with its window (login, downloads); steam://install queues the game
rosetta_steam() {   # rosetta_steam [steam args]
  game_env 0
  first_run_update
  start_steam steam "$STEAM_EXE" ${STEAM_ARGS:#-silent} "$@"
}

# Bring the game files up to date without playing (the ARM64 path runs these files; only Windows Steam updates
# them). A plain Steam start delays a pending update by hours; a launch runs it first. So: -applaunch, wait for the
# new build, end the session as soon as the game appears.
rosetta_update() {   # rosetta_update [--force]
  local acf="$STEAM_DIR/steamapps/appmanifest_$APPID.acf" have latest now
  build() { "$HELPER" steam-build "$acf" "$HOME/Library/Application Support/Steam/appcache/appinfo.vdf" "$STEAM_DIR/appcache/appinfo.vdf"; }
  read have latest <<< "$(build)"
  if [[ ${1:-} != --force ]] && (( latest && have >= latest )); then ok "game up to date (build $have)"; return 0; fi
  game_running && die "Deadlock is running: close it first"
  (( latest )) && step "game update: build $have -> $latest (Windows Steam, in the background)" \
               || step "game update: newest build unknown, letting Windows Steam check"
  game_env 0
  stop_prefix
  local cl="$STEAM_DIR/logs/content_log.txt" cl0 new t0=$SECONDS started=0
  cl0=$( [[ -f $cl ]] && wc -l < "$cl" || print 0 )
  start_steam update "$STEAM_EXE" $STEAM_ARGS -cef-disable-gpu -cef-disable-gpu-compositing -applaunch $APPID $DEADLOCK_ARGS
  while (( SECONDS - t0 < 1200 )); do
    new=$( [[ -f $cl ]] && tail -n +$(( cl0 + 1 )) "$cl" | grep -a "AppID $APPID" || true )
    [[ $new == *'update started'* ]] && (( !started )) && { started=1; step "downloading"; }
    game_running && break
    [[ $new == *'finished update'* ]] && { sleep 3; break; }
    (( SECONDS - t0 > 240 && !started )) && [[ $new != *'Update Required'* ]] && break
    sleep 2
  done
  stop_prefix
  read now latest <<< "$(build)"
  if (( now > have )); then ok "game updated: build $have -> $now"
  elif (( latest && now < latest )); then
    warn "game still on build $now (newest $latest): Windows Steam may need a login (deadlock steam)"; return 1
  else ok "game up to date (build $now)"; fi
}
