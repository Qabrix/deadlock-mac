# Hardware detection and the settings that follow from it. Sourced after common.sh.
# The defaults were tuned on a fanless MacBook Air M4; bigger Macs get no Air compromises.
#   tier efficient    fanless (MacBook Air): the game's frame cap at the display's refresh rate, so menus and the
#                     hideout don't heat the Mac up for frames the display never shows
#   tier balanced     base chip with a fan (MacBook Pro / Mac mini / iMac with M1-M5)
#   tier performance  Pro / Max / Ultra chips (more than 10 GPU cores)
# DL_TIER=<tier> overrides the detection.

hw_detect() {
  [[ -n ${HW_DONE:-} ]] && return 0
  HW_CHIP=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
  HW_PCORES=$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || print 0)
  HW_ECORES=$(sysctl -n hw.perflevel1.physicalcpu 2>/dev/null || print 0)
  HW_MEM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
  HW_MACOS=$(sw_vers -productVersion)
  HW_MACOS_MAJOR=${HW_MACOS%%.*}
  local sp i res
  sp=$(system_profiler -json SPHardwareDataType SPDisplaysDataType 2>/dev/null)
  x() { plutil -extract "$1" raw -o - - <<< "$sp" 2>/dev/null; }
  HW_MODEL=$(x SPHardwareDataType.0.machine_name)
  HW_GPU_CORES=$(x SPDisplaysDataType.0.sppci_cores)
  [[ $HW_GPU_CORES == <-> ]] || HW_GPU_CORES=0
  # the main display's refresh rate ("1710 x 1068 @ 60.00Hz", ProMotion panels report "@ ProMotion")
  HW_REFRESH=60
  for (( i = 0; i < 8; i++ )); do
    res=$(x SPDisplaysDataType.0.spdisplays_ndrvs.$i._spdisplays_resolution) || break
    [[ $(x SPDisplaysDataType.0.spdisplays_ndrvs.$i.spdisplays_main) == spdisplays_yes ]] || continue
    if [[ $res == *ProMotion* ]]; then HW_REFRESH=120
    elif [[ $res =~ '@ ([0-9]+)' ]]; then HW_REFRESH=$match[1]; fi
    break
  done
  if [[ -n ${DL_TIER:-} ]]; then HW_TIER=$DL_TIER
  elif [[ $HW_MODEL == *"MacBook Air"* ]]; then HW_TIER=efficient
  elif (( HW_GPU_CORES > 10 )); then HW_TIER=performance
  else HW_TIER=balanced; fi
  # MetalFX frame interpolation (--framegen) is a macOS 26 API
  HW_FRAMEGEN=$(( HW_MACOS_MAJOR >= 26 ))
  HW_DONE=1
}

# Preset values; DL_* variables of the same meaning win.
hw_preset() {
  hw_detect
  # the game's own frame cap (fps_max): efficient = the display's refresh rate, otherwise the game's saved value
  PRESET_FPS_MAX=${DL_FPS_MAX:-$([[ $HW_TIER == efficient ]] && print $HW_REFRESH || print 0)}
  # NVIDIA Reflex pacing (our nvapi64, Reflex on in the game): its pre-input cap follows the display
  PRESET_REFLEX_FPS=${DL_REFLEX_FPS:-$HW_REFRESH}
  case $HW_TIER in
    efficient)   PRESET_HINT="In game: DLSS Performance (or FSR/stretch ~65 %), low shadows and effects." ;;
    balanced)    PRESET_HINT="In game: DLSS Balanced, medium settings." ;;
    performance) PRESET_HINT="In game: DLSS Quality, high settings; try native resolution on Max/Ultra." ;;
  esac
}

hw_print() {   # key=value lines for `deadlock doctor` and the launcher
  hw_preset
  print -r -- "model=$HW_MODEL"
  print -r -- "chip=$HW_CHIP"
  print -r -- "cores=${HW_PCORES}P+${HW_ECORES}E"
  print -r -- "gpu_cores=$HW_GPU_CORES"
  print -r -- "memory_gb=$HW_MEM_GB"
  print -r -- "macos=$HW_MACOS"
  print -r -- "refresh=$HW_REFRESH"
  print -r -- "tier=$HW_TIER"
  print -r -- "framegen=$HW_FRAMEGEN"
  print -r -- "fps_max=$PRESET_FPS_MAX"
  print -r -- "reflex_fps=$PRESET_REFLEX_FPS"
  print -r -- "hint=$PRESET_HINT"
}
