#!/bin/zsh
# Restores the desktop display mode after a Deadlock session that deadlock started with the Mac switched to
# the game's exclusive-fullscreen resolution (workaround for the cropped start: winemac switches the display mode
# after DXMT has already placed its Metal layer, so the first frames show a crop until borderless -> fullscreen).
#   tools/game-display-mode.sh <dl-helper binary> <state file>
# The state file holds the desktop mode ("<w>x<h>") to restore. Waits up to 10 min for deadlock.exe, then until it
# exits, then restores the mode and removes the state file. ./deadlock kill restores it too.
setopt NO_BG_NICE
DM=$1 STATE=$2
[[ -x $DM && -f $STATE ]] || exit 0
for i in {1..300}; do pgrep -qf '^[A-Za-z]:\\.*\\deadlock\.exe' && break; sleep 2; done
while pgrep -qf '^[A-Za-z]:\\.*\\deadlock\.exe'; do sleep 3; done
[[ -f $STATE ]] || exit 0   # already restored (deadlock kill)
mode=$(<$STATE)
[[ $mode == <->x<-> ]] && "$DM" displaymode set "$mode" >/dev/null 2>&1
rm -f "$STATE"
