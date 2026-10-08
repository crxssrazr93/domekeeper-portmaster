# Dome Keeper for PortMaster

A [PortMaster](https://portmaster.games/) port of [Dome Keeper](https://store.steampowered.com/app/1637320/Dome_Keeper/) (Bippinbits, published by Raw Fury, 2022), a roguelike mining and tower defence game, for Linux handhelds.

The port runs the game's own `domekeeper.pck` on PortMaster's stock Godot 4.3 runtime. No game files are included: you supply the pck from your Steam copy, and the first start adapts it on your device so it fits in 1 GB of RAM.

| | |
|--|--|
| Status | Working on an Anbernic RG35XX H (Knulli, H700, Mali G31, 1 GB RAM): sound, controls, menus and full runs |
| Tester reports (first release) | RG40XX-H (muOS): very slow, froze when a game mode was chosen. RGB30 (ROCKNIX): crashed on New Game. R36S (dArkOS): crashed at the first movement in a run (with zram), black screen after New Game in Korean. Since then the setup no longer needs `stat` (missing on muOS), the lobby needs about half the GPU memory, a run fits in 1 GB, and Korean reaches a run. Retested on 2026-10-07: the RGB30 (ROCKNIX) now runs without crashing. |
| Target | aarch64 PortMaster devices (Knulli, muOS, ROCKNIX, ArkOS and others) with 1 GB RAM or more; x86_64 also packaged |
| Runtimes | `godot_4.3`, Westonpack (`weston_pkg_0.2`) |
| Tested game version | 5.0.8 (Linux and Windows pck) |
| Performance on the RG35XX H | title 60 fps, dome 34 fps, mining 28 to 30 fps; about 400 MB at the title and about 610 MB in a small map run, with about 200 MB to spare (unmodified game: 1.2 GB at the title) |
| First start | about 3.5 minutes on the RG35XX H, shown on PortMaster's patcher screen |

## For players

1. Buy the game on Steam.
2. In Steam, open Dome Keeper's Manage menu and choose Browse local files. Copy `domekeeper.pck` (from the Linux or the Windows version) into `ports/domekeeper/` on your device.
3. Start **Dome Keeper** from the Ports menu. The first start prepares the game on PortMaster's patcher screen (press A to begin, and again to start the game when it is done). It takes about 3.5 minutes on an RG35XX H, longer on slower devices, and needs about 350 MB of free space. Later starts are quick.

Controls, notes and known limitations are in [port/README.md](port/README.md), the file that ships with the port.

## How it works

```
Dome Keeper.sh (PortMaster launcher)
  ├ first start only: PortMaster patcher screen → tools/patchscript
  │     └ godot --headless --script res://setup/port_setup.gd   (patches the pck in place)
  └ westonwrap.sh headless noop kiosk crusty_x11egl                      (Weston + Xwayland, GLES)
      └ godot43 (stock PortMaster godot_4.3 runtime) --main-pack domekeeper.pck
          ├ override.cfg        adds the port's autoloads
          ├ godot/              the pck's project data, with the stub classes in the class cache
          ├ stubs/              offline stand-ins for Steam and PlayFab, PortTweaks, ScaledTexture
          └ cache/              converted sound effects, scaled textures, font stand-ins, title scene
```

The game ships a custom Godot 4.3.1 build with GodotSteam and PlayFab compiled in. The port runs it on the stock 4.3 runtime instead:

* **Stubs** (`port/domekeeper/stubs/`) replace the Steam and PlayFab singletons with offline versions, so the game takes its own non Steam code path and online features are simply off.
* **First start setup** (`port/domekeeper/setup/port_setup.gd`) runs headless against your pck. It copies the project data out of the pack, writes `override.cfg`, and then rewrites the heaviest resources into a cache folder and repoints the pack's `.import` and `.remap` entries to them (the pack directory is patched in place, so nothing from the game leaves your device):
  * sound effects (708 MB as decoded PCM) re-encoded to IMA ADPCM at up to 22 kHz, stereo folded to mono when it is mono in practice (76 MB);
  * the 113 music tracks replaced by streams that load only while playing;
  * only the very large textures (monster, explosion and story sheets) stored smaller, and pixel art kept at its own size so the art stays sharp; scaled textures report their original size so the game's layout is unchanged;
  * the title screen re-saved without the patch notes and credits text, which Godot otherwise shapes up front at a cost of about 140 MB; it is put back when a panel opens;
  * the Chinese, Japanese and Korean fonts replaced by small stand-ins until one of those languages is chosen.
* **PortTweaks** (`port/domekeeper/stubs/PortTweaks.gd`) scales the interface for small 4:3 and square screens, restores deferred text, loads the CJK fonts on demand, and shrinks a map sized render target that only one keeper (the Assessor) uses.
* **Map shader patches** (also in PortTweaks) rewrite the game's two map shaders as they load, which took mining on a single core Mali G31 from about 20 to 28 to 30 fps without changing the picture: the rock shader's `sin()` noise reads a precomputed 256x256 tile, the rock shader skips its outline and damage work in unrevealed rock, and the cave background shader skips pixels where it is invisible. The game files are not changed, and a patch whose expected code is missing (another game version) is skipped.
* **Fresh profile defaults** (in the launcher): offline, gamepad, 60 fps cap, and Render at Half Resolution where the world is drawn at an even number of screen pixels per art pixel, so it looks the same as full resolution (33 to 50 fps in the mine on an RG35XX H).
* **Controller** (in the launcher): the game reads every pad itself, each as its own player, so local split screen works. The built in pad gets PortMaster's mapping for the device, renumbered for Godot's button order (pads that also report keys such as volume or Esc, like the H700 pads, are numbered differently by Godot and SDL). The mapping is passed to the game directly, because Westonpack reloads PortMaster's settings and on muOS that replaced it. A built in pad whose sticks Godot does not accept (muOS on the RG34XX-SP) gets a virtual Xbox 360 pad from `gptokeyb2 -x` instead.
* **`godot_adpcm`** (`src/godot_adpcm/`) is a small C encoder that writes exactly the IMA ADPCM layout Godot's `AudioStreamWAV` expects, with resampling and mono folding. It ships as static aarch64 and x86_64 binaries.

The full story, with measurements and every approach that failed, is in [docs/PORTING.md](docs/PORTING.md).

## Repository layout

| Path | Contents |
|--|--|
| `port/` | Exactly what ships to `ports/` on the device (plus the encoder binaries after building) |
| `src/godot_adpcm/` | Source of the sample encoder |
| `build/` | Encoder build (`Dockerfile`, `build.sh`), `package.sh`, and the memory profiling tools (`build_godot_profiling.sh`, `massif_gpu.sh`) |
| `tests/` | Local test harnesses, a virtual gamepad, and test only Godot scripts in `tests/devtools/` |
| `tools/` | `pckls.py`, lists the files and sizes inside a Godot pck |
| `docs/` | Porting notes |

## Building

Requirements: Docker, zip.

```
build/build.sh      # godot_adpcm for aarch64 and x86_64, static, into port/domekeeper/tools/
build/package.sh    # domekeeper.zip, ready to unzip into ports/
```

## Testing on a PC

The harnesses run the game on the x86_64 build of PortMaster's `godot_4.3` runtime (the same official 4.3 export template the device uses), on a private Xwayland server at a handheld resolution, driven by a virtual gamepad. The game runs in bubblewrap with only the virtual pad in `/dev/input`.

Requirements: Xwayland, xdpyinfo, bubblewrap, ImageMagick, ffmpeg, Python 3 with `python-evdev`, write access to `/dev/uinput`, and `godot43.x86_64` from PortMaster's `godot_4.3` runtime.

```
export GAME_PCK=/path/to/domekeeper.pck GODOT=/path/to/godot_4.3/godot43.x86_64
tests/prepare.sh                     # copy of the pck with the first start setup applied, in tests/out/game
tests/localtest.sh 640x480 "wait 20; shot title; tap dright; press A; wait 3; shot options"
AUTORUN=regular-small tests/localtest.sh 640x480 "wait 50; press A; wait 8; shot run"
tests/resolutions.sh                 # title, options and pause menu at six resolutions
tests/launchertest.sh "wait 15; shot started"   # the real launcher against a mock PortMaster
```

Each run prints whether the game was still alive and its peak memory, and writes screenshots, the game log and a memory trace to `tests/out/<tag>/`. `AUTORUN` (handled by `tests/devtools/autorun.gd`) starts a single player run on the given map archetype; `tests/devtools/diag.gd` logs Godot's memory monitors and, with `--texdump`, every live texture. `tests/vpad.py` documents the step syntax.

For heap profiles, `build/build_godot_profiling.sh` builds Godot 4.3 with symbols and `build/massif_gpu.sh` runs it under valgrind massif with the real GPU renderer (see docs/PORTING.md, section 5).

## Testing on the device

`tests/device/` holds the tools used on the RG35XX H over SSH (Knulli; EmulationStation's local API on port 1234 launches and stops ports):

* `knulli.sh` runs a command on the device, `knulli_shot.sh` takes a screenshot from the framebuffer (GL output does not show up in fbgrab), `fbfps.py` counts presented frames.
* `devpad.py` presses buttons by writing to the controller's own input device, with the same step syntax as `tests/vpad.py`.
* `dk_lobby.sh` restarts the game and walks into the singleplayer lobby.
* `tests/devtools/perfdiag.gd`, added to `override.cfg` as an autoload, logs fps, draw calls and shader counts every 2 s and takes commands from `/tmp/dk_cmd`: switch shaders, lights or nodes off, replace a shader's code live, dump viewport sizes and material parameters. This is how the map shader costs in docs/PORTING.md were measured. With `tests/devtools/autorun.gd` and `-- --autorun=regular-small` on the game's command line, a run starts without driving the lobby.

## Known limitations

* Online services (online multiplayer, leaderboards) are unavailable. Local splitscreen is untested.
* On 480x320 screens the interface scale is capped so the Options panel still fits, which leaves small text.
* Sound effects are at most 22 kHz, and the very large texture sheets are at half resolution.
* On single core Mali G31 devices (H700) the mine runs at about 50 fps with Render at Half Resolution (on by default where it looks the same, see below) and about 33 fps without, rather than 60. The rest of the frame time is the game's map effects; a simpler cave background was measured (at most 3 fps more, visibly less detail) and left out. The game's Simple Backgrounds and Reduced Particle Effects options change neither frame rate nor memory there.
* ROCKNIX needs Panfrost (as for every Westonpack port).

## Credits and licenses

* Dome Keeper by Bippinbits, published by Raw Fury. Not affiliated; buy the game to play it.
* [Godot Engine](https://godotengine.org/) (MIT). The ADPCM encoder follows Godot's own `ResourceImporterWAV` encoder.
* `stubs/LazyAudioStream.gd` and the pack patching approach in `setup/pck_patcher.gd` come from Knifethrower's [PM Porting Tools](https://github.com/Knifethrower/PM-Porting-Tools) (0BSD).
* [Westonpack](https://github.com/binarycounter/Westonpack) by binarycounter, the PortMaster team.
* Everything written for this port (launcher, stubs, setup, encoder, scripts, docs) is MIT licensed, see [LICENSE](LICENSE). The port package carries these notices in `port/domekeeper/licenses/`.
