# deadlock-mac

Play [Deadlock](https://store.steampowered.com/app/1422450/Deadlock/) on an Apple-silicon Mac, with a launcher and a
runtime tuned for it: our own builds of Wine and of [DXMT](https://github.com/3Shain/dxmt) (Direct3D 11 on Metal), with
DLSS running on Apple's MetalFX, NVIDIA Reflex pacing and a lot of smaller CPU and GPU savings
measured in real matches.

> **Unofficial.** Not made or endorsed by Valve, Apple or CodeWeavers. Deadlock has no Mac version; this runs the
> Windows game through a compatibility layer, at your own risk. The game's files are never modified (see
> [What it changes](#what-it-changes)).

## Requirements

- A Mac with Apple silicon (M1 or newer; any Air, Pro, mini, iMac, Studio). Intel Macs are not supported.
- macOS 15 or newer.
- About 55 GB of free disk space (game, runtimes, shader caches).
- A Steam account with Deadlock in its library.

## Tested on

| | |
|---|---|
| Mac | MacBook Air 15-inch (M4, 2025), fanless |
| Chip | Apple M4: 10-core CPU (4 performance + 6 efficiency cores), 10-core GPU |
| Memory | 24 GB |
| Display | built-in 2880 × 1864 panel |
| Game resolution | 1710 × 1068 |
| macOS | 27.0.1 |
| Cooling | **thermal-pad mod** (thermal pads that let the chassis take more heat from the chip) |

On this Mac, at 1710 × 1068 with DLSS Performance and low graphics settings: 60 fps (the cap) in early fights, around 50 fps in
late-game fights once the Air heats up. A fanless Air slows its CPU when the case gets warm, so an unmodified Air
will drop sooner; a Mac with a fan (MacBook Pro, Mac mini, Mac Studio) holds its speed much longer.

## Install

Open Terminal and paste:

```sh
curl -fsSL https://raw.githubusercontent.com/Qabrix/deadlock-mac/main/install.sh | zsh
```

The installer downloads the newest release (about 270 MB), installs Rosetta 2 if it is missing (macOS may ask for your
password), sets up a Windows Steam inside Wine and opens **Deadlock Launcher** from `~/Applications`. Run the same
command again later to update; your login, game and settings stay.

## First start

The launcher walks you through it:

1. **Windows Steam in Wine**: one click, a few minutes.
2. **Log in and download Deadlock**: Steam's window opens; log in and confirm the install (~40 GB). The launcher notices
   when the game is there.
3. **DLSS (optional)**: needs one file from Apple's free Game Porting Toolkit, see [DLSS](#dlss) below. Without it
   the game uses its own upscaler (FSR or *stretch*).

Then press **Play**.

## DLSS

DLSS runs on Apple's MetalFX upscaler here, but the game only turns it on when it finds Apple's signed `nvngx.dll`.
That file comes with Apple's free Game Porting Toolkit and may not be shared, so you import it once yourself:

1. Open [developer.apple.com/games/game-porting-toolkit](https://developer.apple.com/games/game-porting-toolkit/)
   and sign in with your Apple Account (free, no paid developer membership needed).
2. Download the newest **Game Porting Toolkit** `.dmg` (tested: 4.0 beta 2 and 3.0). You don't need to open or
   install it.
3. In Deadlock Launcher, click **Choose .dmg…** and pick the file. Or in Terminal (use your file's name):

   ```sh
   ~/Library/Application\ Support/deadlock-mac/bin/deadlock gptk ~/Downloads/Game_Porting_Toolkit_4.0.dmg
   ```

   It answers *DLSS enabled*. The `.dmg` can be deleted afterwards.
4. Start the game and set the upscaler to **DLSS** in its video settings. **Performance** is a good start on a
   MacBook Air; on faster Macs try Balanced or Quality.

## Rosetta or ARM64

The launcher offers two ways to run the game:

| | Rosetta (default) | ARM64 |
|---|---|---|
| How | Windows Steam and the game in one Wine prefix, Wine translated by Rosetta 2 | arm64 Wine, only the game's own code is translated (by [FEX](https://github.com/FEX-Emu/FEX)), built on [neutron](https://github.com/lixsldotnet/neutron) |
| Needs | nothing else | **Mac Steam** running and logged in (the game talks to it); Windows Steam still downloads game updates |
| First matches | smooth | can hitch for ~15 minutes while FEX fills its code cache |

Both use the same game files, settings, keybinds and hero builds.

**Recommended: Rosetta.** On the test Mac (below) it ran better in our matches: higher frame rates, and smoother
even after ARM64's code cache had warmed up; it also has no hitching phase at the start. ARM64 is there for experimenting, and as the way
forward once Apple phases Rosetta out (macOS 27 is the last release with full Rosetta support).

## Settings that adapt to your Mac

The defaults were tuned on a fanless MacBook Air M4. On first use the launcher detects your Mac and picks a tier:

| Tier | Macs | What changes |
|---|---|---|
| efficient | MacBook Air (no fan) | the game's frame cap at your display's refresh rate, so menus and the hideout don't heat the Mac for frames it can't show |
| balanced | M1–M5 with a fan (MacBook Pro, mini, iMac) | no frame cap |
| performance | Pro, Max and Ultra chips | no frame cap |

Reflex pacing follows your display's refresh rate (60 Hz, 120 Hz ProMotion, …). The launcher
shows a suggestion for the in-game settings that fit your tier.

## Options

| Launcher | Command line | What |
|---|---|---|
| Map | `--map NAME` | start straight into a custom map (see below) |
| Parkour helpers | `--parkour` | on `sv_cheats` maps: **Q** checkpoint, **E** teleport back + restart the stopwatch, **T** stopwatch start/stop, **H** clear; the stopwatch is drawn into the game's frame |
| Scroll-wheel jump helpers | `--wheel` | for Jump bound to both Space and the wheel: one wheel flick = one jump, the wheel works while Space is held, a quick double Space makes the wheel raw for wall jumps |
| DLSS | `--no-dlss` | DLSS (MetalFX) once the toolkit file is imported |
| Frame generation (experimental) | `--framegen auto\|1` | **not recommended for now**: still buggy and adds input latency. Off by default; macOS 26+, with DLSS |
| VSync | `--vsync` | even frame pacing; default is the lowest-latency presentation |
| Metal HUD | `--hud` | Apple's performance overlay |
| Show Steam's window | `--steam-window` | Rosetta: Steam's window visible (it is hidden by default because drawing it costs ~1 CPU core in matches) |

The `deadlock` command is at `~/Library/Application Support/deadlock-mac/bin/deadlock` (`deadlock --help` lists
everything: `setup`, `install`, `update`, `kill`, `gptk`, `mods`, `doctor`).

### Custom maps

Click **+** next to the map picker and choose a map's `.vpk` (or `deadlock mods install <file.vpk>`). A map is mounted
only when you start with it, and loaded a second time once you are in it, because a custom map's own data (for
example its hero) is only used from a second load. Some maps (Jump Control, Jump School) ship their own hero list,
which hides newer heroes until you quit the game; start a normal match from a fresh launch.

## What it changes

- Wine prefix, runtimes and logs live in `~/Games/Deadlock.noindex` (the name keeps Spotlight out).
- Game settings written while the game is closed: the frame cap (`fps_max`, efficient tier only), separate video
  settings for DLSS and non-DLSS sessions (the game resets them when the GPU it sees changes), console and keybind
  files for the map/parkour helpers, and the custom maps you chose (in `game/citadel/addons`, removed again on the next
  normal start).
- The Mac's display mode switches to the game's resolution while it runs in exclusive fullscreen, and back afterwards
  (otherwise the game starts cropped).
- Windows Steam keeps running after a match so the next start is quick, and is closed about 2 minutes after you quit
  the game (idle under Wine it would keep the CPU busy). `DL_STEAM_IDLE_STOP=0` keeps it running.
- With Bluetooth headphones, the Mac's default microphone switches to the built-in one when the game starts: Deadlock
  always opens the default microphone for voice chat, and a headset whose own microphone is in use drops to call
  quality (mono, muffled). `DL_BT_MIC=1` keeps the headset's microphone.
- The game starts with `+v8_jitless 1`: its interface scripts run without generating machine code at runtime, which
  Rosetta would otherwise have to translate again and again. A launch option, no file change; `DL_V8_JIT=1` turns it
  off.
- Nothing is installed into the system, and `/Applications/Steam.app` is not modified.

## Troubleshooting

- **The game doesn't start, or Steam waits:** Windows Steam sometimes waits on a dialog (cloud sync conflict, *Play
  anyway?*). Press **Kill**, turn on *Show Steam's window*, press **Play** and answer it.
- **Steam's window is black:** expected when *Show Steam's window* is off; the game still runs.
- **Bluetooth headphones sound like a phone call (muffled, mono):** something has the headset's microphone open.
  The launcher moves the game to the built-in microphone, but other apps (Discord, FaceTime) do the same thing: pick
  the MacBook microphone in those apps or in System Settings → Sound → Input. Restart the game afterwards, because it
  sets up its sound when it starts. Bluetooth on a Mac always runs at 44.1 kHz (macOS has no LDAC); a cable gives
  higher rates.
- **Hitches in the first ARM64 matches:** FEX is filling its code cache; it gets smooth after ~15 minutes of play.
- **Newer heroes locked:** you started a session with Jump Control or Jump School; quit and play from a fresh start.
- **Logs:** launcher → More → *Open logs folder*, plus `~/Library/Logs/neutron/` for ARM64. `deadlock doctor` prints
  what is installed and the settings it chose. Please attach both to bug reports, with your Mac model.

## Uninstall

```sh
~/Library/Application\ Support/deadlock-mac/bin/deadlock kill
rm -rf ~/Applications/Deadlock\ Launcher.app ~/Library/Application\ Support/deadlock-mac ~/Games/Deadlock.noindex
```

The last folder holds the game (~40 GB) and your Windows Steam login.

## Building

Releases are built by the maintainer; see [docs/BUILDING.md](docs/BUILDING.md) for the source pins, patch queues and
build scripts.

## Credits and licenses

Built on [Wine](https://www.winehq.org) (via [winecx](https://github.com/dappermint/winecx), CrossOver's macOS changes),
[DXMT](https://github.com/3Shain/dxmt), [neutron](https://github.com/lixsldotnet/neutron), [FEX](https://github.com/FEX-Emu/FEX),
[DXVK-macOS](https://github.com/Gcenx/DXVK-macOS), [MoltenVK](https://github.com/KhronosGroup/MoltenVK) and
[llvm-mingw](https://github.com/mstorsjo/llvm-mingw). The performance config ideas credit the Deadlock community.
Our own scripts and the launcher are MIT licensed ([LICENSE](LICENSE)); the patches in `patches/` and the runtimes
carry the licenses of the projects they belong to, listed in [THIRD_PARTY.md](THIRD_PARTY.md).

Deadlock and Steam are trademarks of Valve Corporation. Apple, Mac, macOS, Metal and MetalFX are trademarks of
Apple Inc.
