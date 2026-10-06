#!/bin/bash

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

# Knulli names the buttons for games by position, as SDL does: "a" is the bottom button, which
# is labelled B on these devices. Swap a/b and x/y so the buttons act as labelled, like in the
# system menus.
if [ "$CFW_NAME" = "knulli" ]; then
  swap_ab() { sed -E 's/,a:/,@:/g; s/,b:/,a:/g; s/,@:/,b:/g; s/,x:/,@:/g; s/,y:/,x:/g; s/,@:/,y:/g'; }
  export SDL_GAMECONTROLLERCONFIG="$(printf '%s\n' "$SDL_GAMECONTROLLERCONFIG" | swap_ab)"
  swap_ab < "$SDL_GAMECONTROLLERCONFIG_FILE" > /tmp/gamecontrollerdb_ab.txt &&
    export SDL_GAMECONTROLLERCONFIG_FILE=/tmp/gamecontrollerdb_ab.txt
fi

GAMEDIR="/$directory/ports/domekeeper"
CONFDIR="$GAMEDIR/conf"
godot_runtime="godot_4.3"
godot_executable="godot43.$DEVICE_ARCH"
weston_runtime="weston_pkg_0.2"

cd "$GAMEDIR"
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1
# Device, system and memory details for bug reports (tools/portlog.sh)
# The files a bug report needs; named in log.txt and on screen only when something fails
export PORT_REPORT_FILES="ports/domekeeper/log.txt and setup_log.txt"
source "$GAMEDIR/tools/portlog.sh"
port_header "Dome Keeper launcher"
mkdir -p "$CONFDIR"

# The game data comes from the user's own copy: domekeeper.pck from the Steam Linux build
# (the Windows build's pck works too).
if [ ! -f "$GAMEDIR/domekeeper.pck" ]; then
  pm_message "Missing domekeeper.pck. Copy it from your Steam copy of Dome Keeper into ports/domekeeper/ (see README.md)."
  sleep 8
  pm_finish
  exit 1
fi

for runtime in "$godot_runtime" "$weston_runtime"; do
  if [ ! -f "$controlfolder/libs/${runtime}.squashfs" ]; then
    if [ ! -f "$controlfolder/harbourmaster" ]; then
      pm_message "This port requires the latest PortMaster to run, please go to https://portmaster.games/ for more info."
      sleep 5
      exit 1
    fi
    $ESUDO $controlfolder/harbourmaster --quiet --no-check runtime_check "${runtime}.squashfs"
  fi
done

godot_dir=/tmp/godot
weston_dir=/tmp/weston
$ESUDO mkdir -p "$godot_dir" "$weston_dir"
if [[ "$PM_CAN_MOUNT" != "N" ]]; then
  $ESUDO umount "$godot_dir" 2>/dev/null
  $ESUDO umount "$weston_dir" 2>/dev/null
fi
$ESUDO mount "$controlfolder/libs/${godot_runtime}.squashfs" "$godot_dir"
$ESUDO mount "$controlfolder/libs/${weston_runtime}.squashfs" "$weston_dir"
port_mounted "$godot_runtime" "$godot_dir/$godot_executable"
port_mounted "$weston_runtime" "$weston_dir/westonwrap.sh"

# Size and modification time of each file, as "stat -c '%s %Y'" prints them (muOS has no stat)
file_stamp() {
  if command -v stat >/dev/null; then stat -c '%s %Y' "$@" 2>/dev/null; return 0; fi
  local f
  for f in "$@"; do [ -e "$f" ] && echo "$(ls -lnL "$f" | awk '{print $5}') $(date -r "$f" +%s)"; done
  return 0
}
# First run (and again after the game updates its pck): adapt the user's pck to the stock
# Godot 4.3 runtime and to 1 GB devices. setup/port_setup.gd explains every step; each one
# skips work already done, so an interrupted run just continues next time.
# Large textures are stored at the screen's scale of the game's 1920x1080 design: the factor is
# 1 / min(W/1920, H/1080), rounded, from 2 to 4 (3 at 640x480 and 720x720). It is part of the
# stamp, so another screen size prepares the textures again.
texture_factor="$(awk -v w="${DISPLAY_WIDTH:-640}" -v h="${DISPLAY_HEIGHT:-480}" 'BEGIN { s = w / 1920; if (h / 1080 < s) s = h / 1080; f = int(1 / s + 0.5); if (f < 2) f = 2; if (f > 4) f = 4; print f }')"
# Colour art (not palette index art) is stored as ASTC on ARM devices, whose GPUs all decode it,
# with PortMaster's astcenc; elsewhere it is scaled like the rest.
texture_astc=""
[ "$DEVICE_ARCH" = "aarch64" ] && [ -x "$controlfolder/astcenc.aarch64" ] && texture_astc="$controlfolder/astcenc.aarch64"
texture_mode="$texture_factor ${texture_astc:+astc}"
pck_stamp="$(file_stamp domekeeper.pck) $texture_mode"
port_files domekeeper.pck override.cfg
if [ ! -f override.cfg ] || [ "$(cat cache/.setup_stamp 2>/dev/null)" != "$pck_stamp" ]; then
  port_log "setup: needed (first run or game update; stamp '$(cat cache/.setup_stamp 2>/dev/null)', pck '$pck_stamp')"
else
  port_log "setup: up to date"
fi
if [ ! -f override.cfg ] || [ "$(cat cache/.setup_stamp 2>/dev/null)" != "$pck_stamp" ]; then
  export GAMEDIR godot_dir godot_executable DEVICE_ARCH controlfolder texture_factor texture_astc texture_mode
  chmod +x "$GAMEDIR/tools/patchscript"
  export PATCHER_FILE="$GAMEDIR/tools/patchscript"
  export PATCHER_GAME="Dome Keeper"
  export PATCHER_TIME="3 to 10 minutes"
  if [ -f "$controlfolder/utils/patcher.txt" ]; then
    port_log "running the setup (tools/patchscript), its log is setup_log.txt"
    source "$controlfolder/utils/patcher.txt"
  else
    pm_message "This port requires the latest version of PortMaster."
    sleep 5
    $ESUDO umount "$godot_dir" "$weston_dir" 2>/dev/null
    pm_finish
    exit 1
  fi
  # tools/patchscript writes the stamp only on success, from the pck as the setup left it
  if [ "$(cat cache/.setup_stamp 2>/dev/null)" != "$(file_stamp domekeeper.pck) $texture_mode" ]; then
    port_log "setup failed"
    port_report
    pm_message "Preparing the game failed, see ports/domekeeper/setup_log.txt. To report it, send $PORT_REPORT_FILES."
    sleep 8
    $ESUDO umount "$godot_dir" "$weston_dir" 2>/dev/null
    pm_finish
    exit 1
  fi
fi

# Godot only flushes print() output at exit in release builds, so the FPS lines (--print-fps)
# would be lost when the firmware closes the game; flush every line instead.
grep -q "^run/flush_stdout_on_print" override.cfg 2>/dev/null ||
  printf '\n[application]\n\nrun/flush_stdout_on_print=true\n' >> override.cfg

# Defaults for a fresh profile: answer the online services prompt (multiplayer servers are not
# available on this port), turn off crash reports, cap the frame rate and prefer the gamepad.
options_dir="$CONFDIR/godot/app_userdata/Dome Keeper"
if [ ! -f "$options_dir/options.txt" ]; then
  mkdir -p "$options_dir"
  echo '{"onlineMultiplayerDecided":true,"allowOnlineMultiplayer":false,"allowCrashReports":false,"fullscreen":true,"vsync":true,"targetfps":60,"singleplayerUseGamepad":true}' > "$options_dir/options.txt"
fi

# Godot numbers joypad buttons from BTN_JOYSTICK (0x120) upwards, then BTN_MISC to BTN_JOYSTICK,
# and skips lower key codes. SDL numbers every key code in ascending order, so on pads that also
# report keys like volume or Esc the SDL mapping's bN indices point at the wrong buttons in Godot.
# Renumber them using the pad's key bitmap.
godot_joy_mapping() {
  local mapping="$1" name="${1#*,}" dev="" ev wbits=64 n i b w code
  name="${name%%,*}"
  for ev in /sys/class/input/event*/device; do
    [ "$(cat "$ev/name" 2>/dev/null)" = "$name" ] && { dev="$ev"; break; }
  done
  [ -n "$dev" ] || { echo "$mapping"; return; }
  case "$(uname -m)" in aarch64|x86_64) ;; *) wbits=32 ;; esac
  local words=($(cat "$dev/capabilities/key")) codes=()
  n=${#words[@]}
  for ((i = 0; i < n; i++)); do
    w=$((16#${words[n-1-i]}))
    for ((b = 0; b < wbits; b++)); do
      (( (w >> b) & 1 )) && codes+=($((i * wbits + b)))
    done
  done
  local -A godot_idx=()
  local g=0 sdl=0 out="" f
  for code in "${codes[@]}"; do (( code >= 0x120 )) && godot_idx[$code]=$((g++)); done
  for code in "${codes[@]}"; do (( code >= 0x100 && code < 0x120 )) && godot_idx[$code]=$((g++)); done
  local -A sdl_to_godot=()
  for code in "${codes[@]}"; do
    [ -n "${godot_idx[$code]}" ] && sdl_to_godot[$sdl]=${godot_idx[$code]}
    sdl=$((sdl + 1))
  done
  IFS=, read -ra fields <<< "$mapping"
  for f in "${fields[@]}"; do
    if [[ "$f" =~ ^([^:]+):b([0-9]+)$ ]]; then
      [ -n "${sdl_to_godot[${BASH_REMATCH[2]}]}" ] || continue
      f="${BASH_REMATCH[1]}:b${sdl_to_godot[${BASH_REMATCH[2]}]}"
    fi
    out+="$f,"
  done
  echo "$out"
}

# Only Godot gets the renumbered mapping (exported after gptokeyb starts, since gptokeyb is an
# SDL program). westonwrap evals its arguments, so a value with spaces cannot be passed there.
godot_mapping=""
while IFS= read -r line; do
  [ -n "$line" ] && godot_mapping+="$(godot_joy_mapping "$line")"$'\n'
done <<< "$SDL_GAMECONTROLLERCONFIG"

# gptokeyb1 is unresponsive on muOS, where gptokeyb2 is used instead (as in the Dicey Dungeons port)
if [ "$CFW_NAME" = "muOS" ] && [ -n "$GPTOKEYB2" ]; then
  $GPTOKEYB2 "$godot_executable" -c "$GAMEDIR/domekeeper.gptk" &
else
  $GPTOKEYB "$godot_executable" -c "$GAMEDIR/domekeeper.gptk" &
fi
pm_platform_helper "$godot_dir/$godot_executable"
export SDL_GAMECONTROLLERCONFIG="$godot_mapping"
port_log "controller mapping for the game: $(printf '%s\n' "$SDL_GAMECONTROLLERCONFIG" | head -n 1)"

port_log "starting the game, UI scale ${DK_UI_SCALE:-automatic}"
# westonwrap replaces XDG_RUNTIME_DIR; pass the real one on so ALSA can reach PipeWire for sound.
REAL_XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
# DK_UI_SCALE overrides the automatic UI scale (1.33 at 640x480 and 720x720, 1.19 at 480x320, 1.0 on 16:9 screens).
$ESUDO env $weston_dir/westonwrap.sh headless noop kiosk crusty_x11egl \
  LD_PRELOAD= XDG_DATA_HOME="$CONFDIR" XDG_RUNTIME_DIR="$REAL_XDG_RUNTIME_DIR" DK_UI_SCALE="${DK_UI_SCALE:-0}" \
  "$godot_dir/$godot_executable" --resolution "${DISPLAY_WIDTH}x${DISPLAY_HEIGHT}" -f \
  --rendering-driver opengl3_es --audio-driver ALSA --print-fps --main-pack "$GAMEDIR/domekeeper.pck"

port_exit
$ESUDO $weston_dir/westonwrap.sh cleanup
if [[ "$PM_CAN_MOUNT" != "N" ]]; then
  $ESUDO umount "$godot_dir"
  $ESUDO umount "$weston_dir"
fi
pm_finish
