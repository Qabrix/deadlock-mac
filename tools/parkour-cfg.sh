#!/bin/zsh
# --parkour's game side: cfg/dl_parkour_init.cfg binds F9 to "exec dl_parkour" (the game runs it at start via
# +exec dl_parkour_init); winemac writes each command into cfg/dl_parkour.cfg and presses F9. "off" empties
# dl_parkour.cfg, so F9 (the bind may stay in the game's config) does nothing outside --parkour.
#   tools/parkour-cfg.sh <game/citadel folder> on|off
set -u
dir=$1/cfg
[[ -d $dir ]] || { print -u2 "parkour-cfg: no $dir"; exit 1; }
if [[ $2 == on ]]; then
  print -r -- 'bind "F9" "exec dl_parkour"' > "$dir/dl_parkour_init.cfg"
  : > "$dir/dl_parkour.cfg"
elif [[ -f $dir/dl_parkour.cfg ]]; then
  : > "$dir/dl_parkour.cfg"
fi
