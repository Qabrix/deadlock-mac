#!/bin/zsh
# Deadlock mods (custom maps etc.), switchable: the game mounts game/citadel/addons/pakNN_dir.vpk. Mods are stored in
# $DL_ROOT/mods/store/<name>.vpk; `on` copies them into addons as pak50+, `off` removes exactly the files this script
# placed (list in addons/.deadlock-mac-mods), so normal matches run without them. Some maps replace game data for
# every match while mounted (Jump Control and Jump School ship their own hero list: newer heroes show as locked).
# bin/deadlock calls `on` for --map / --mods and `off` otherwise.
#   tools/mods.sh install <file.vpk> [name] | on [name,...] | off | list | maps
#   maps: "<map> <mod>" per map a stored mod carries (one mod can hold several)
set -u
here=${0:A:h}
source "${here:h}/lib/common.sh"
STORE="$DL_ROOT/mods/store"
ADDONS="$CITADEL/addons"
LIST="$ADDONS/.deadlock-mac-mods"
mkdir -p "$STORE"
case ${1:-list} in
  install)
    [[ -f ${2:-} ]] || die "usage: deadlock mods install <file.vpk> [name]"
    name=${3:-${2:t:r}}; cp -c -p "$2" "$STORE/$name.vpk" && ok "mod '$name' stored (its maps: deadlock mods maps)" ;;
  on)
    game_running && die "Deadlock is running: mods change on the next start"
    mkdir -p "$ADDONS"; "$0" off >/dev/null
    n=50; : > "$LIST"
    # `on a,b`: only those, in that order (a lower pak number wins where two mods ship the same file); `on` alone: all
    if [[ -n ${2:-} && ${2:-} != 1 ]]; then
      mods=(); for nm in ${(s:,:)2}; do [[ -f $STORE/$nm.vpk ]] && mods+=("$STORE/$nm.vpk") || warn "no mod '$nm' (deadlock mods list)"; done
    else
      mods=("$STORE"/*.vpk(N))
    fi
    for m in $mods; do
      cp -c -p "$m" "$ADDONS/pak${n}_dir.vpk" && print -r -- "pak${n}_dir.vpk ${m:t:r}" >> "$LIST"; (( n++ ))
    done
    (( n > 50 )) && ok "mods on: $(cut -d' ' -f2 "$LIST" | tr '\n' ' ')" || warn "no mods in $STORE" ;;
  off)
    game_running && die "Deadlock is running: mods change on the next start"
    # (.deadlock-gptk-mods: the list of the project this one grew out of)
    for l in "$LIST" "$ADDONS/.deadlock-gptk-mods"; do
      [[ -f $l ]] || continue
      while read -r f name; do [[ -n $f ]] && rm -f "$ADDONS/$f"; done < "$l"
      rm -f "$l"
    done ;;
  list)
    print "stored: $(ls "$STORE" 2>/dev/null | sed 's/\.vpk$//' | tr '\n' ' ')"
    print "active: $( [[ -f $LIST ]] && cut -d' ' -f2 "$LIST" | tr '\n' ' ' || print none)" ;;
  maps)
    for m in "$STORE"/*.vpk(N); do "$HELPER" vpk-maps "$m" | sed "s/\$/ ${m:t:r}/"; done ;;
  *) die "usage: deadlock mods install <file.vpk> [name] | on | off | list | maps" ;;
esac
