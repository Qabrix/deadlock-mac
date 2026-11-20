#!/bin/zsh
# --map's game side. A custom map needs a second, separate load: started with +map, the map's own data (e.g. its
# hero) isn't in use yet. `on` writes the command into cfg/dl_map_reload.cfg; Wine's Mac driver runs it once through
# the F9 console channel (WINE_MAC_CONSOLE, +exec dl_parkour_init) 2 s after the game first captures the cursor,
# i.e. once the player is in the map. `off` removes it. Prints the mod that carries the map (empty for a stock map).
#   tools/map-cfg.sh <game/citadel folder> on <map> | off
set -u
here=${0:A:h}
dir=$1/cfg
[[ -d $dir ]] || { print -u2 "map-cfg: no $dir"; exit 1; }
if [[ $2 == on ]]; then
  print -r -- "// deadlock-mac tools/map-cfg.sh
map $3" > "$dir/dl_map_reload.cfg"
  "$here/mods.sh" maps | awk -v m="$3" '$1 == m { print $2; exit }'
else
  rm -f "$dir/dl_map_reload.cfg"
fi
