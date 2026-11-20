# Third-party software

The release runtimes are built from these projects. The exact versions and every change we make are in
[docs/BUILDING.md](docs/BUILDING.md) and `patches/`. The license texts are in each project's source at the pinned
version.

| Part | License | Source |
|---|---|---|
| Wine | LGPL-2.1-or-later | https://gitlab.winehq.org/wine/wine |
| winecx (CrossOver's macOS changes on Wine) | LGPL-2.1-or-later | https://github.com/dappermint/winecx, https://www.codeweavers.com/crossover/source |
| DXMT | LGPL-2.1-or-later | https://github.com/3Shain/dxmt |
| neutron (tool script, sandbox profile, patches) | LGPL-2.1-or-later | https://github.com/lixsldotnet/neutron |
| FEX | MIT | https://github.com/FEX-Emu/FEX |
| LLVM (in DXMT's shader converter) | Apache-2.0 WITH LLVM-exception | https://github.com/llvm/llvm-project |
| Proton steam_helper | BSD-3-Clause | https://github.com/ValveSoftware/Proton |
| Proton lsteamclient | Steamworks SDK license (Valve) | https://github.com/ValveSoftware/Proton |
| DXVK-macOS | Zlib | https://github.com/Gcenx/DXVK-macOS |
| MoltenVK | Apache-2.0 | https://github.com/KhronosGroup/MoltenVK |
| Wine Mono | MIT and the licenses of its parts | https://github.com/madewokherd/wine-mono |
| mingw-w64 runtime (in the Windows DLLs) | ZPL-2.1 and public domain | https://www.mingw-w64.org |
| GnuTLS, Nettle, GMP, libtasn1, libidn2, libunistring, p11-kit | LGPL | their projects |
| FreeType | FreeType License (FTL) | https://freetype.org |
| SDL3, sdl2-compat | Zlib | https://github.com/libsdl-org/SDL |

The patches in `patches/` are under the license of the project they patch.

Not included: Apple's Game Porting Toolkit. For DLSS the player imports one file (`nvngx-on-metalfx.dll`) from their
own download of it; it is never part of a release.

lsteamclient is Valve's code under the Steamworks SDK license, the same component Valve ships in every Proton release.
Steam and Deadlock are trademarks of Valve Corporation.
