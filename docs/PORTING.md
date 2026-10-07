# Porting notes: Dome Keeper

A record of how this port was made, what was measured, and every approach that failed, so the next Godot port (or the next person) does not walk the same dead ends.

## 1. Survey

| Item | Finding |
|--|--|
| Store | Steam app 1637320. Linux and Windows builds, both tested (game version 5.0.8.14). |
| Engine | Custom Godot 4.3.1 build (`4.3.1.rc.custom_build`) with GodotSteam and PlayFab (services, party peer, lobby) compiled in |
| Renderer | Already `gl_compatibility` (GLES3), so it can run on handheld GPUs |
| Pack | `domekeeper.pck`, 1.25 GB, pack format 2. 2509 lossless `.ctex` textures (decoded to RGBA in memory), 1384 PCM sound effects (708 MB decoded), 151 Ogg files (113 of them music, 355 MB) |
| Memory | 1215 MB at the title on the stock runtime with stubs only |

There is no ARM build, but the game logic is all GDScript in the pack, so the route is the usual one for Godot games: run the pck on PortMaster's stock runtime for the matching engine version, and supply whatever the custom engine added.

## 2. Getting it to start

* **Stubs.** `Steam`, `PlayFabServices`, `PlayFabPartyMultiplayerPeer` and `PlayFabLobby` are engine classes or singletons in the custom build. GDScript stand-ins with the methods and signals the game uses (`port/domekeeper/stubs/`) make the scripts compile. `Steam` stays absent as an engine singleton, so the game picks its own `PlatformFacadeDummy` path.
* **Project data.** The stub classes need entries in the global class cache. The setup script copies the pack's project data (`.godot/`) to `godot/` next to the pack, adds the two classes to `global_script_class_cache.cfg`, drops the GDExtension list, and sets `use_hidden_project_data_directory=false` in `override.cfg` so Godot reads that folder.
* **res:// fallback.** Files missing from the pck resolve from the game folder on disk, which is how the stubs, the setup script and the cache load.

Script errors went from about 770 to none and the title rendered at 640x480. The remaining work was memory.

## 3. Memory

Measured on the x86_64 runtime at 640x480 as rss plus swap (the test PC swaps idle pages, so plain RSS undercounts), together with Godot's video memory monitor. On Mali GPUs the video memory is shared RAM, so the device total is roughly CPU plus GPU.

### Round 1

| Stage | Title CPU | Title GPU |
|--|--|--|
| Stubs only | 1215 MB | 278 to 411 MB |
| + lazy music (113 tracks) | 653 MB | 411 MB |
| + IMA ADPCM sound effects (708 MB to 180 MB) | 433 MB | 411 MB |
| + ScaledTexture (418 textures with a side of 512 px or more halved) | 529 MB | 93 MB |

### Round 2 (target about 500 MB on 1 GB devices)

| Stage | Title CPU | Small map run CPU | Run GPU |
|--|--|--|--|
| Round 1 | 533 MB | 457 MB | 244 MB |
| + deferred patch notes text (cleared at `node_added`) | 518 MB | | |
| + CJK font stand-ins, 22 kHz and mono folding for sound effects (176 MB to 76 MB) | 465 MB | | |
| + title scene saved with the panel text in metadata | 298 MB | 363 MB | 218 MB |
| + Assessor render target at 2x2 when no Assessor plays | | 365 MB | 203 to 221 MB |

The estimated device total in a small map run is about 575 MB, against 1.2 GB plus video memory unmodified. Larger maps add more (see "Still to do").

### Round 3 (crash when a run starts, reported on 1 GB rk3326 and rk3566 devices)

Starting a run crashed on the test device too. On Mali's vendor driver the GPU memory (`/sys/kernel/debug/mali0/gpu_memory`, in pages) reached 482 MB in the level, with 921 MB of RAM in use, and the game died. Measured on the device, small map:

| Build | Level GPU | Level RAM in use | Lobby GPU peak |
|--|--|--|--|
| Round 2 | 482 MB, crashed | 921 MB | |
| + texture factor 3 at 640x480 | about 280 MB | 766 MB | about 450 MB |
| + ASTC for colour art, map layers at half resolution | 248 MB | 755 MB | 441 MB (a few seconds, while the level builds) |
| + map render targets saved at 2x2 | 247 MB | | 394 MB (intro 187 to 97 MB) |
| + world and UI viewports saved at 2x2, every map layer halved from its first size | 170 MB | peak 664 MB | 202 MB |

Godot's own texture counter on the PC: lobby peak 319 MB to 164 MB, level 167 MB to 101 MB.

* **Texture factor.** Textures of 512 px or more are now divided by the ratio between the 1920x1080 design and the screen (3 at 640x480, at least 2, at most 4), instead of always by 2. The launcher passes it to the setup and it is part of the setup stamp, so a different screen size redoes the textures from the original `.ctex` files, which stay in the pack.
* **ASTC.** Colour art (more than 64 colours, no mipmaps) is halved and compressed to ASTC 4x4 with PortMaster's `astcenc.aarch64` (in the PortMaster folder on every aarch64 firmware), 1 byte per pixel instead of 4. The Mali G31 decodes it in hardware. Palette index art cannot be compressed: its colour values are palette coordinates, and any lossy change reads a different colour. 72 of the 424 scaled textures qualify.
* **Map layers at half resolution.** `ViewportRocks`, `ViewportLights`, `ViewportBackgroundAlpha` and `ViewportCrackImpact` are map sized render targets. PortTweaks halves each one in `frame_pre_draw`, before its first draw, scales its canvas transform by 0.5 and doubles the sprites that show it. `Map.gd` places background alpha sprites at `size.x / 2`, so that viewport's canvas origin and the sprites already placed are shifted to match. `Map.gd` itself is compiled GDScript (`.gdc`) and is not changed.
* **Render targets saved large.** `Map.tscn` saves `ViewportRocks`, `ViewportLights` and `ViewportBackgroundAlpha` at 2048x2048, and `BundleResourceTracker.tscn` its viewport at 2000x2000. Godot allocates a render target as soon as a scene is instantiated, before the game's code sets the real size, so every map (the intro's shader preload map, the lobby, the level) briefly held about 64 MB of render targets, and Godot's texture counter jumped to 300 MB on entering the lobby. The setup patches the saved size to 2x2 directly in the exported binary scenes (a `Vector2i` is its variant tag 45 and two int32, and 2048x2048 is stored once). Re-saving the scenes through Godot is not possible in the setup: their scripts need the game's autoloads to compile. The launcher's setup stamp carries a setup version, so installs prepared before this run the new step.
* **World and UI viewports saved at 1920x1080.** `ViewportContainer.tscn` (the camera's world and UI viewports, used by the lobby and the level) and `LandingStage.tscn` save their viewports at 1920x1080; the scripts size them to the screen on the first frame. The full HD targets were allocated first, and the Mali driver kept that memory for the whole stage. Patched to 2x2 like the map scenes. A probe that logs every frame where Godot's texture memory moves by 8 MB or more, with every viewport at that moment, found them.
* **Map layers halved from the first size.** `HalfViewport.gd` is put on each map layer as it enters the tree (on `ViewportRocks` and `MapLights`, which have scripts of the game's, as a subclass of that script made at runtime). Its `_set` turns every size the game assigns into half that size, so the full size target is never allocated. `Map.gd` passes a `Vector2`; `MapLights` is sized with `set_size()`, which `_set` does not see, so the per frame check still halves it before its first draw. `ViewportTopEffects` is halved too now. `TinyViewport.gd` keeps BundleResourceTracker's viewport at 2x2 from the start.
* **Render targets on Mali.** A render target costs about 4.5 times its RGBA size in GPU memory on the vendor driver (r20p0), and `disable_3d` saves only about 1 MB each. Halving a target that has already been drawn gives back much less than its size, since freed GPU memory is not returned promptly.
* **Korean, Japanese, Chinese.** With these changes Korean reaches a run on the device: the lobby takes about 6 s longer to load (the real font data is loaded and its glyphs are rendered) and needs about 40 MB more.

### What each change does

* **Lazy music.** The game preloads its soundtrack. Each track under `res://content/music/` is replaced by a `LazyAudioStream` (from PM Porting Tools) that loads the real Ogg only while it plays.
* **IMA ADPCM.** `src/godot_adpcm/godot_adpcm.c` is a port of Godot 4.3's own `_compress_ima_adpcm`: a 4 byte header per channel, low nibble first, stereo channels encoded separately and byte interleaved. Godot's encoder only exists in the editor, hence a separate tool. Sounds above 22050 Hz are resampled (windowed sinc low pass), and stereo whose side signal is 30 dB or more below the mid signal is folded to mono. `--verify` decodes the way `AudioStreamPlaybackWAV` does: SNR 26 to 49 dB on the game's samples, short UI chimes lowest. Static aarch64 and x86_64 builds give byte identical output.
* **ScaledTexture.** Textures with a side of 512 px or more are stored at half resolution, 8192 px or more at a quarter (the texture size limit of GLES3 class Mali GPUs). `ScaledTexture` is an `ImageTexture` with `size_override`, so it reports the original size and atlas regions, frame grids and tile sets stay correct.
* **Palette index art.** The sprites are not colour images: shaders read `texture(palette, vec2(start_r + input.r, start_b + input.b))`, so every colour value is a coordinate into a palette. Bilinear downscaling blends coordinates into wrong colours, so images with 64 or fewer distinct colours are resized nearest neighbour. Verified by checking that scaled sheets contain no new colours.
* **Title text.** The title screen's hidden PatchNotesPanel and CreditsPanel hold 193 labels. Hidden, they are 0 px wide, so every character wraps onto its own line (13872 lines for one label), and Godot keeps HarfBuzz buffers, ICU bidi data and glyph arrays per line: a heap peak of 401 MB settling at 261 MB. Setup saves the scene again with the text moved to `port_text` metadata, and PortTweaks restores it while a panel is visible.
* **CJK fonts.** 36 MB of font data for Chinese, Japanese and Korean is preloaded for every language. Setup repoints those fonts to stand-ins (a small Latin font plus the real path in metadata), and PortTweaks copies the real font data into the stand-ins when one of those languages is selected.
* **Assessor render target.** `BundleResourceTracker` is a map sized `SubViewport` used only by the Assessor keeper. PortTweaks keeps it at 2x2 unless an Assessor is in the run.

## 4. Screen sizes

The game is laid out for 1920x1080 and Godot scales that design down to the screen, so on a 640x480 screen text shrinks to a third. PortTweaks sets `Window.content_scale_factor` to

```
s = max(1, min(0.5, w/1280, h/1080) / min(w/1920, h/1080))
```

which aims for half size text, but never shows fewer than 1280x1080 design units, because the largest menu (Options, about 1040 units tall) must still fit with its Cancel and Apply row.

| Resolution | Scale |
|--|--|
| 640x480 | 1.33 |
| 480x320 | 1.19 |
| 720x720 | 1.33 |
| 854x480, 1280x720, 1920x1152 | 1.0 |

16:9 screens are already limited by height, so they cannot be scaled up without clipping that panel. `DK_UI_SCALE` in the launcher overrides the result. Checked at all six sizes: title, options, new game popup, run and pause menu (`tests/resolutions.sh`).

### World zoom

The UI scale does not reach the lobby (its game mode, loadout and keeper panels are drawn in the world) or the mine. The world and each player's HUD are drawn in the SubViewports of `systems/camera/ViewportContainer.gd`, whose `size_2d_override` holds the 1920x1080 design view; at 640x480 a world pixel at the game's camera zoom of 4 covers 1.33 screen pixels, and the lobby text is a few pixels tall. The game already enlarges this view for split screen by dividing that override by 1.75. PortTweaks does the same after each resize (on `logic_size_changed`, ignoring the emits for camera zoom changes) with a factor that draws the design at least at half size, at most 1.5: 2 screen pixels per world pixel at 640x480 (1.5) and 720x720 (1.33), 1.0 on 16:9 screens. The render target sizes are unchanged, so GPU memory is the same; less of the world is in view. The lobby camera follows the keeper, so its panels come into view as the keeper moves toward them, as they already did at 4:3 without the zoom. Checked in the lobby (640x480, 720x720) and in a run on the device. `DK_WORLD_ZOOM` overrides the factor (1 = the game's view).

The lobby (a ViewportContainer under `stages/loadout/MultiplayerloadoutStage.gd`) gets a larger factor of its own, 7/3 screen pixels per world pixel: 1.75 at 640x480 and 1.56 at 720x720. The value was picked by comparing 1.25, 1.5, 1.75 and 2.0 on the RG35XX H; 1.25 was still too small, and 1.75 was the choice. `DK_LOBBY_ZOOM` overrides it.

### Short menus drawn larger, large popups fitted

The UI scale has to keep the Options panel on screen, so short menus stay small. PortTweaks draws them larger, as they look on a 1280x720 screen (2/3 of design size), at most 1.5x: 1.5 at 640x480, 1.33 at 720x720, 1.0 on 16:9 screens.

* **Title menus.** MainMenu (New Game, Options, Quit) is scaled about its bottom centre, AdditionalMenu (Updates, Credits) about its bottom left. When the two would meet, the factor is limited and MainMenu's pivot moves so its left edge lands right after AdditionalMenu (scaling about pivot p moves a corner to `origin + p * (1 - s)`). With Continue shown the row is wider, about 1.2x at 640x480.
* **Pause menu.** `fadeIn` tweens MenuPanel's scale from 0 to 1 and slides the corner boxes in by position, so a scale on the panel is overwritten on every open. The whole `PauseMenu` CanvasLayer is scaled about the screen centre instead. Each corner box is moved back to its corner through its anchors (`a' = 0.5 + (a - 0.5) / s`) and drawn at 1/s, as it enters the tree, because the menu's own `_ready` already records the slide's start and end positions. The controls box is enlarged up to the menu's left edge. Options, tutorials and the player list are added to the same layer when opened, and get the inverse scale (pivot at the screen centre in their own coordinates), so they lay out exactly as from the title. The restart and quit confirmations are moved left when they would leave the screen.
* **Landing screen.** Its centre text and the "Press anything to continue" hint (bottom right) are scaled about their anchors.
* **Large popups.** Every popup is a full screen CenterContainer holding a PanelContainer at its minimum size. A panel larger than the screen (Key Bindings at 640x480) is scaled down to fit with a 2% margin. The CenterContainer grows to the panel's size, so the panel is measured against the screen and centred through its pivot, and Container layout resets a child's scale on every sort, so the fit runs again on `sort_children`. Some popups are added a screen height below the view and slide in (the gadget choice after a gadget is brought to the dome), so the fit also runs again whenever the CenterContainer moves.

Checked on the PC at 640x480 (`tests/devtools/autorun.gd` modes `options` and `popups`, which can also call a method such as `_on_ButtonOptions_pressed` on the loaded scene) and on the RG35XX H: title, every Options category, Key Bindings and the keeper input popups, the pause menu with Options, Key Bindings and the restart confirmation, and the landing hint.

The intro's two gradient backgrounds are turned 270 degrees and sized for 16:9. On 4:3 screens they end about 85 design units short of the top, and the map the intro draws underneath (layer -10, to compile the map shaders early) showed through as a blue strip above the bippinbits logo. PortTweaks lengthens them to reach the top edge.

## 5. How the problems were found

* **Texture census.** `tests/devtools/diag.gd --texdump` lists every live texture (scene tree, resource cache, font glyph caches) with size, format and bytes, largest first.
* **Heap profiles.** valgrind massif on a symbolized build of the same engine (`build/build_godot_profiling.sh`: Godot 4.3-stable, `template_release`, `debug_symbols=yes`). valgrind cannot run on the test PC's CachyOS loader (it is built for newer CPU instructions than valgrind supports), so `build/massif_gpu.sh` runs it in an Ubuntu 22.04 container with `/dev/dri` and `/run/udev` passed through, drawing to an `Xwayland -ac` display on the host. That run found the 140 MB text shaping spike and the 64 MB of sound effects still held after ADPCM.
* **Pack contents.** `tools/pckls.py --by-ext` sums the pack by file type.

## 6. What failed and why

1. **Godot Mod Loader script extensions** to patch a custom engine property (`Window.multi_viewport_focus`): the Steam export bakes `_custom_features="steam,disable_mods"`, and custom features only come from the exported `project.binary`, not `override.cfg`. Not needed anyway: release templates skip that check.
2. **Testing with the Godot 4.3 editor binary** is misleading: it adds the `editor` feature tag and reports errors that release builds do not. Use the PortMaster runtime's x86_64 build.
3. **A 1920x1080 window on a 640x480 test display** shows only the top left corner. Always pass `--resolution`.
4. **Writing to res:// from the setup script** fails in pack mode. Setup writes to the absolute folder given with `--out`.
5. **ETC2 compression on the device**: Godot's etcpak encoder is editor only.
6. **`PortableCompressedTexture2D.size_override`** does not change `get_size()`, so sprites drew at half size. `ImageTexture.set_size_override` does, but is not serialized, so `ScaledTexture` reapplies it from an exported `display_size`.
7. **Keeping short sound effects as PCM**: even those under 256 KB cost 66 MB.
8. **A uid cache remap** for audio underestimated the savings: most audio is referenced by path, so the fixes repoint `.import` entries in the pack instead.
9. **Clearing the title text at `SceneTree.node_added`** saved only 15 MB: Godot shapes text at `NOTIFICATION_ENTER_TREE`, which comes before `node_added`. The scene is re-saved instead.
10. **Replacing the CJK fonts with `take_over_path` from an autoload**: the game's autoloads had already loaded them. `override.cfg` keeps the project's order for existing autoloads and new ones (the port's) come last, so the replacement happens at pack level.
11. **Bilinear downscaling** broke palette index sprites (wrong colours), see section 3.
12. **massif in headless mode** overstated text costs: every label is 0 px wide there. Profiles now use the GPU container run.
13. **An apparent 1.3 GB leak** was the memory sampler picking valgrind's Godot process. The sampler now follows the game's own PID.
14. **Repacking the title scene in `--script` mode** prints compile errors for scripts that use autoload names. Harmless: the saved scene references the same scripts by path (compared byte for byte with a repack done inside a normal game process).
15. **A signal arity mismatch** in the PlayFab stub (`score_submission_failed` emitted with an argument the game's handlers do not take) caused script errors. Fixed in the stub.
16. **UI scale, first versions**: scaling by height alone made 720x720 text smaller; keeping 720 design units of height visible (640x480 at 1.5) cut off the Options panel's Cancel and Apply row at 640x480, 480x320 and 854x480. The current formula keeps 1080 units visible.
17. **Test harness problems**: stopping bubblewrap (which does not forward signals) and then Xwayland made Godot die on the lost X connection and raised desktop crash dialogs. The harnesses now stop Godot first, use `bwrap --die-with-parent` and `ulimit -c 0`. Starting a game before a fresh Xwayland accepted connections, or two harnesses on one display, gave black screenshots; each harness now waits for its server and takes a display from `DISP`. `pkill -f` with a literal pattern also matched the calling shell.

18. **Scaling the pause menu's panel** had no effect: the menu's open animation sets its scale from 0 to 1. Moving the corner boxes after the menu's `_ready` put them off screen, because `_ready` already starts their slide in from the old positions.
19. **Desktop crash dialogs from the PC tests**: Godot segfaults while shutting down this game (and when the landing scene is loaded on its own, outside a run). `ulimit -c 0` or `1` does not stop systemd-coredump on this kernel. The test autoload now ends the process with `OS.kill` (SIGKILL, which never dumps core) and the runner stops Godot with SIGKILL. Godot's stdout is block buffered then, so debug output goes to stderr.
20. **Fitting a popup only when it is added.** The pivot that centres a fitted panel depends on where its CenterContainer is on screen. The gadget choice is added a screen height below the view and slides up, so a pivot worked out at that moment put the panel above the screen once it arrived: the game sat paused with "Paused" at the top and the choice visible for about three frames (a tester on a 720x720 RGB30). Checked after the fix at 640x480, 480x320, 720x720, 854x480, 1280x720 and 1920x1152 with the test autorun's `RELIC_AT` hook, which opens the gadget choice as a delivered gadget does.

## 7. On the device (Anbernic RG35XX H, Knulli)

H700 SoC (4 x Cortex A53), a single core Mali G31 (`/sys/class/misc/mali0/device/gpuinfo`: "Mali-G31 1 cores"), 1 GB RAM, 640x480. Tested with the Linux 5.0.8 pck.

### Results

| Item | Result |
|--|--|
| First start setup | about 3.5 minutes, peak 213 MB, shown on PortMaster's patcher screen |
| Title | 60 fps, about 400 MB |
| Singleplayer lobby | 19 fps before the shader patches, 29 to 30 after |
| Small map run | dome 34 fps, mining 28 to 30 fps (19 to 22 before); about 610 MB RSS with about 200 MB available |
| Sound, controls, exit hotkey | working |

### Setup on the device

* **The setup itself ran out of memory.** In `--script` mode with a `SceneTree` main loop, Godot adds the project's autoloads after `_init`, and the game's autoloads load most of the game: the process passed 1 GB after the setup had finished (1.14 GB peak on the PC). `port_setup.gd` is now a plain `MainLoop`, which gets no autoloads. A `MainLoop` script cannot set a success exit code (Godot 4 reports failure), so the setup writes `cache/.setup_ok` after its last step and `tools/patchscript` checks that instead.
* **Texture scaling** decodes the `.ctex` payload directly (PNG or WebP images inside the GST2 container, size from the header) instead of `load().get_image()`, which skips the resource cache and small textures early. Peak 154 MB on the PC, 213 MB on the device.
* **The encoder's resampler** was rewritten with an integer position and one precomputed kernel per phase (output byte identical at 48, 44.1 and 32 kHz): about 20 times faster on the device, 3.0 s down to 0.15 s per 10 s stereo clip.
* **Progress screen.** The launcher hands the setup to PortMaster's patcher (`utils/patcher.txt`, a LÖVE screen that runs `PATCHER_FILE` and shows each line it prints). `tools/patchscript` runs Godot, keeps the full output in `setup_log.txt` and shows only the setup's `PORT_SETUP:` lines. The setup prints those with `printerr`: release builds do not flush stdout on print (`application/run/flush_stdout_on_print` defaults to false), so `print` lines would only arrive at the end.

### Launcher

* **Controller.** The game reads the pads itself (Godot joypad input), each as its own player, so local split screen works with an external pad. Godot numbers joypad buttons from `BTN_JOYSTICK` (0x120) upwards, then `BTN_MISC`, and ignores lower key codes, while SDL numbers every key code in ascending order. The H700 pads also report Esc and the volume keys (codes 1, 114, 115), so every `bN` in PortMaster's mapping was 3 too high for Godot (L1 acted as accept). `godot_joy_mapping` finds the built in pad by the mapping's GUID (the name can differ: muOS maps its `muOS-Keys` pad as `Deeplay-keys`) and renumbers the mapping from the pad's key bitmap. The mapping reaches the game as a `VAR=value` argument to `westonwrap.sh`: Westonpack sources PortMaster's `control.txt` again, which on muOS exports the original mapping over anything the launcher exported. Westonpack evals its arguments, so the mapping is passed as one line with the spaces in its name replaced (only the GUID is matched). Godot 4.3 only opens a joystick with `ABS_X` and `ABS_Y`, or `ABS_RX` and `ABS_RY`; muOS on the RG34XX-SP reports the built in sticks as `ABS_Y`, `ABS_Z`, `ABS_RY` and `ABS_RZ`, so Godot ignored that pad completely. For such a pad the launcher starts `gptokeyb2 -x` (a virtual Xbox 360 pad read through SDL with PortMaster's mapping) and gives the real pad a mapping that binds nothing. Otherwise gptokeyb only supplies the exit hotkey (`domekeeper.gptk` maps no buttons; gptokeyb2 on muOS).
* **Sound** needs the real `XDG_RUNTIME_DIR`: Westonpack replaces it, and ALSA then cannot reach PipeWire. The launcher passes the original on.

### Frame rate: the map shaders

The GPU is the limit: the main thread is about half idle and the GPU runs at its top clock (696 MHz). `tests/devtools/perfdiag.gd` measured each part live in the lobby (fps):

| Change | fps |
|--|--|
| none | 19 to 24 |
| every ShaderMaterial removed | 51 |
| `map_main_stones_new` (rock) removed | 33 |
| `map_background_edges` (cave background) removed | 24 |
| rock shader reduced to one texture read | 36 |
| rock shader: only its noise kept / only its outlines kept | 24 / 27 |
| rock shader in `mediump` | +0 |
| `ViewportLights` (3024x912, updated every frame) paused or at 1/2 and 1/4 size | +0 |

Every part of the rock shader loads the single GPU core, so removing one part only moves the limit to another. What helped was skipping work, not making it cheaper. Three patches, applied by PortTweaks to the game's shader code as it loads (the game files are not changed, and each patch is skipped if the code it expects is missing):

1. **Noise tile.** The rock shader builds two value noises per pixel from eight `sin()` hashes each. The lattice values never change, so they are computed once into a 256x256 tile, and `noise()` reads it at the smoothstep shifted position, where the hardware bilinear filter performs the same smoothstep interpolation. Lobby 19 to 25 fps.
2. **Invisible cave background.** The cave background only shows where the tunnel mask is open, but it ran its full shader for every pixel. It now computes its own alpha first (two reads) and skips the rest where that is 0. Exact, since such pixels are not blended. Mine 24 to 28 fps.
3. **Unrevealed rock.** Unrevealed rock (rock falloff at or below the game's own stone paint threshold of 0.01) only shows the depth gradient; outlines and damage only occur next to tunnels, which are always revealed. The falloff, cutout and gradient are computed first and about 20 texture reads are skipped there. Mine 29 to 33 fps. On a still view of the mine, 47 of 307200 pixels differ, nearly all by one colour step.

Not worth it: an outline baked into the tunnel mask (best case +2 fps, and the mask is a CPU image updated on every dig, so an exact bake needs a full resolution GPU pass per dig); a 4 tap outline (+0 to +2); a simpler cave background on top of the three patches (at most +3 fps in large open areas, visibly less detail).

### Compared with an unofficial port

An existing unofficial handheld build ("Extreme Compress Mod", the stock `godot43` binary with an embedded pack rebuilt from a community Android port of 5.0.7) was run under the same launcher. Its map shaders and map scene are the same as Steam's (byte identical shaders, the scene differs only in resource ids), and its Android add-on is touch controls and mod loader plumbing. With the 218 MB pack embedded in the binary, it used 720 MB at the title and was killed by the kernel for lack of memory twice while loading the lobby. Nothing in it changes the rendering, and its memory savings (8 kHz 8 bit samples, downscaled textures) are covered by the ADPCM and texture steps here.

### What failed on the device and why

1. For one release every game used `gptokeyb2 -x`, one virtual Xbox 360 pad for all real pads. That merged an external pad and the built in one into one player, which broke local split screen (reported on a Powkiddy RGB30 with ROCKNIX), so the virtual pad is now only the fallback for pads Godot cannot open.
2. Godot's `--print-fps` printed nothing at first: release builds do not flush stdout on print. The launcher now adds `application/run/flush_stdout_on_print=true` to `override.cfg`, and the frame rate appears in `log.txt`.
3. Fixed waits before menu presses failed whenever loading took longer; the device scripts wait for the perf log to show the expected scene.
4. The launcher first compared the setup stamp with the pck's size and date from before the setup, which the setup changes by patching the pck in place: every fresh setup was reported as failed. A rerun on the device passed only because nothing changed; `tests/launchertest.sh` with `FRESH=1` caught it.
5. On the test PC, `/tmp` is a 20 GB tmpfs: copies of the pck there filled it and truncated files, which showed up as a corrupt pck. Scratch copies now go to disk.
6. With the virtual pad, `CRUSTY_BLOCK_INPUT=1` did not hide the real pad from Godot, and every press arrived twice. An empty mapping for the real pad still moved menus two steps per D-pad press, because Godot maps an unbound hat to the D-pad; binding the hat to unused buttons fixed it. On muOS the launcher's exported mapping was replaced by Westonpack (see Controller above), which caused the same double steps there until the mapping was passed as a westonwrap argument.
7. PortMaster tracks a port by the line `# PORTMASTER: <zip>, <script>` at the top of its launcher. Without it, harbourmaster inserted the line into every launcher the first time it downloaded a runtime, while one of them was running, and bash then read the shifted file and stopped with a syntax error. The launcher now carries the line.

## 8. Still to do

* Memory and frame rate in long runs and on medium to huge maps.
* Other devices: rk3326 and rk3566 handhelds (ArkOS, ROCKNIX with Panfrost, muOS).
* The lobby holds about 200 MB of GPU memory and the level about 170 MB. Textures counted by Godot are 111 and 83 MB, about 37 MB of them image textures; the rest are render targets and generated textures.
* Local splitscreen.
* Confirm on ROCKNIX with Panfrost.
