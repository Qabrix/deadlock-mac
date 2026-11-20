#!/bin/zsh
# Keeps Deadlock's per-user files (hero builds, hero settings, keybinds, user convars) the same in both Steam
# clients: the Windows Steam of the Rosetta path and Mac Steam of the arm64 path have their own userdata folders, and
# their Steam Cloud syncs of the same files fail or conflict (2026-10-25: builds picked on one path were missing on
# the other). For every file the newer copy wins; the one it replaces is kept once per day in
# <userdata>/1422450/.deadlock-mac-sync/<date>/. Video settings and fps caps stay per path (bin/deadlock copies the Rosetta video settings to Mac Steam).
# Run before every start; safe to run by hand: tools/sync-game-cfg.sh (DL_SYNC_DRY=1: only list)
set -u
here=${0:A:h}
source "${here:h}/lib/common.sh"
R=("$DL_PREFIX"/drive_c/Program\ Files\ \(x86\)/Steam/userdata/*/1422450(N))
M=("$HOME"/Library/Application\ Support/Steam/userdata/*/1422450(N))
[[ -n ${R[1]:-} && -n ${M[1]:-} ]] || exit 0
R=${R[1]} M=${M[1]}
files=(remote/cfg/cached_hero_builds.kv3 remote/cfg/citadel_hero_settings.lst remote/cfg/citadelkeys_personal.lst
       remote/user_convars.vcfg remote/user_keys.vcfg local/cfg/user_convars_0_slot0.vcfg
       local/cfg/user_keys_0_slot0.vcfg local/cfg/user_keys_0_slot1.vcfg local/cfg/user_keys_0_slot2.vcfg
       local/cfg/user_keys_0_slot3.vcfg)
day=$(date +%Y%m%d) n=0
for f in $files; do
  a="$R/$f" b="$M/$f"
  [[ -f $a || -f $b ]] || continue
  if [[ -f $a && -f $b ]]; then
    cmp -s "$a" "$b" && continue
    if [[ $a -nt $b ]]; then src=$a dst=$b dstroot=$M; else src=$b dst=$a dstroot=$R; fi
  elif [[ -f $a ]]; then src=$a dst=$b dstroot=$M
  else src=$b dst=$a dstroot=$R; fi
  if [[ ${DL_SYNC_DRY:-0} == 1 ]]; then print "would copy $f: $([[ $dstroot == $M ]] && print 'Rosetta -> arm64' || print 'arm64 -> Rosetta')"; continue; fi
  if [[ -f $dst ]]; then
    bk="$dstroot/.deadlock-mac-sync/$day/${f:h}"; mkdir -p "$bk"
    [[ -f $bk/${f:t} ]] || cp -p "$dst" "$bk/${f:t}"
  fi
  mkdir -p "${dst:h}"; cp -p "$src" "$dst" && (( n++ ))
done
(( n )) && print "synced $n Deadlock settings file(s) between the Rosetta and arm64 Steam (newest wins)"
exit 0
