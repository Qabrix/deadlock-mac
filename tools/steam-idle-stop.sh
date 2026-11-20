#!/bin/zsh
# Stops the Windows Steam session (Wine) once Deadlock has been closed for a while. The launcher keeps Steam running to
# hand the next launch to it, but nothing ever stopped it: idle under Wine, steamwebhelper's renderer + wineserver
# kept ~1.5 cores busy for hours after a match.
#   started by bin/deadlock play (Rosetta path):  steam-idle-stop.sh <wine> <wineserver> <prefix> [grace seconds, default 120]
# Waits up to 10 min for deadlock.exe; after it exits, waits <grace> s (a relaunch in that window just continues the
# watch), then asks Steam to quit (steam.exe -shutdown) and, if it is still there after 30 s, ends the Wine session.
setopt NO_BG_NICE
WINE=$1 WINESERVER=$2 GRACE=${4:-120}   # separate from export: "A=1 export B" would set A for export only
export WINEPREFIX=$3
game() { pgrep -qf '^[A-Za-z]:\\.*\\deadlock\.exe'; }
steam() { pgrep -qf "${WINEPREFIX:t}/.*[Ss]team.exe|C:.*\\\\Steam\\\\steam.exe"; }
for i in {1..300}; do game && break; sleep 2; done
game || exit 0
while true; do
  while game; do sleep 5; done
  waited=0
  while (( waited < GRACE )) && ! game; do sleep 5; (( waited += 5 )); done
  game || break
done
if steam; then   # a clean quit first (Steam saves its state); whatever is left goes with the session below
  "$WINE" 'C:\Program Files (x86)\Steam\steam.exe' -shutdown </dev/null >/dev/null 2>&1 &!
  for i in {1..15}; do steam || break; sleep 2; done
fi
game && exit 0   # started again meanwhile: leave everything alone
# end the whole session: steam.exe can quit and leave steamwebhelper (its CEF UI) + the wineserver running, which
# kept a core busy all night (2026-11-19); with no game running nothing else lives in this prefix
"$WINESERVER" -k 2>/dev/null
exit 0
