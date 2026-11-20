# Building the runtimes

Players don't need any of this: the installer downloads prebuilt runtimes. This is how the maintainer builds them,
and what every binary in a release is made of.

## What a release contains

| Asset | Contents |
|---|---|
| `deadlock-mac-<v>.tar.gz` | this repository, `bin/dl-helper`, `Deadlock Launcher.app` |
| `runtime-rosetta-<v>.tar.xz` | x86_64 Wine (runs under Rosetta 2), our DXMT in `lib/dxmt`, DXVK for Steam's web UI, MoltenVK |
| `runtime-arm64-<v>.tar.xz` | neutron's tool folder (arm64 Wine + ARM64EC, FEX, Proton's lsteamclient) with our Wine pieces, DXMT and FEX |

Every Mach-O in a release targets macOS 15 or older (the packager checks it), and the arm64 code we compile targets
`armv8.4-a`, the M1's instruction set.

## Sources and patches

| Part | Upstream, pinned | Our changes |
|---|---|---|
| Wine (Rosetta) | [dappermint/winecx](https://github.com/dappermint/winecx) `e0aa380780b7` (branch wine1117: CrossOver 26.3's macOS changes on Wine 11.17); deps from the CrossOver 26.3.0 source drop | `patches/wine-rosetta/*.patch`, in order |
| DXMT (Rosetta) | [3Shain/dxmt](https://github.com/3Shain/dxmt) `50102f994b40` | `patches/dxmt/0001-deadlock-mac.patch` |
| neutron | [lixsldotnet/neutron](https://github.com/lixsldotnet/neutron) `0ac2574` (Wine 11.19, Proton `5b89db94` lsteamclient, LLVM 15.0.7, llvm-mingw 20260908) | `patches/arm64/neutron-tool-0001-no-python-prompt.patch` (the tool script) |
| Wine (ARM64) | Wine 11.19 + neutron's `patches/wine` | `patches/arm64/arm64-wine-deadlock-mac.patch` |
| DXMT (ARM64) | DXMT `50102f994b40` | `patches/arm64/arm64-dxmt-full.patch` (ours + neutron's display patches) |
| FEX (ARM64) | the FEX commit neutron pins | `patches/arm64/arm64-fex-main-with-neutron-macos.patch` (neutron's FEX patches + our SMC fix), then `arm64-fex-0002..0006` |
| llvm-mingw's lld | llvm-mingw 20260908 | `patches/arm64/lld-0001`, `lld-0002` (ARM64EC linking) |
| DXVK (Steam's UI) | [Gcenx/DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) `v1.10.3-20230507-repack` | none |
| MoltenVK | 1.4.2 release | none |

What the patches do, in short:

- **Wine, both paths:** per-program DLL folders (DXMT only for `deadlock.exe`), msync tuning (one sync object per cache
  line, events that skip a server round trip), QoS for the game's main thread and the wineserver's request loop,
  macOS efficiency-class reporting so Source 2 sizes its job pool right, precise short sleeps, cheaper PE/unix
  transitions, CoreAudio minimum period and mix rate, MMCSS priorities, relative mouse-look without coalescing,
  scroll-wheel jump gating, the console channel used by `--map` and the parkour helpers (with the stopwatch drawn by
  DXMT into the frame), a modern driver version for DLSS.
- **DXMT:** DLSS on MetalFX Temporal, NVIDIA Reflex pacing in nvapi64, MetalFX frame generation that keeps the UI out
  of interpolation, CAS sharpening, vsync pacing, render-pass merging and trimming, lossless render targets,
  front-end trims, frame-time logs.
- **FEX:** AFP off for ARM64EC with the RPRES fix, an L1-only lookup cache, x86 memory order exactly where Source 2's
  lock-free code needs it, x86 `PAUSE` as a short timed wait where the CPU supports it.

## Steps

Needs Xcode (not only the Command Line Tools) with its Metal toolchain (`xcodebuild -downloadComponent MetalToolchain`),
Homebrew `bison flex autoconf cmake ninja meson pkgconf gnutls freetype`, and ~60 GB of disk.

1. **Rosetta Wine:** `maintainer/build-wine.sh` (clones winecx at the pin, applies `patches/wine-rosetta`, builds Wine,
   DXVK and the deps into `$DL_ROOT/runtime/wine-<id>`). `maintainer/build-llvm15.sh` builds the LLVM 15 DXMT links
   against.
2. **neutron:** clone neutron at the pin into `$DL_ROOT/build/arm64/neutron-src` and run its
   `./build.sh $DL_ROOT/build/arm64/work`; then apply the `patches/arm64` Wine, FEX and DXMT patches to the trees in
   `work/src` (Wine), `work/src/FEX-main` and a DXMT checkout at `$DL_ROOT/build/arm64/dxmt-ours-arm64-v2`.
3. **DXMT (Rosetta):** a DXMT checkout with `patches/dxmt` at `$DL_ROOT/build/dxmt-src`.
4. **PGO profile:** DXMT is built with a profile from real matches (`$DL_ROOT/pgo/dxmt.profdata`): build DXMT once with
   `-fprofile-generate`, play a match or two, merge the `.profraw` files with `llvm-profdata merge`.
5. **Release pieces:** `maintainer/build-public.sh all` builds DXMT (both paths), the ARM64 Wine pieces and FEX for
   macOS 15 / M1 in APFS clones of those trees, pausing whenever the game runs. `maintainer/build-arm64-deps.sh`
   builds gnutls, nettle, gmp and freetype for the ARM64 runtime (neutron's build copies the build machine's
   Homebrew libraries, which target that machine's macOS).
6. **Package:** `maintainer/package.sh <version>` puts the three assets and `SHA256SUMS` into
   `$DL_ROOT/build/public/release/<version>`; upload them to a GitHub release with that tag.

Steps 1–4 are long (hours on an M4) and so far have only been run on the maintainer's machine, piece by piece; if you
try them from scratch, please report what breaks.
