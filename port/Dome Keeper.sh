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

GAMEDIR="/$directory/ports/domekeeper"
CONFDIR="$GAMEDIR/conf"
godot_runtime="godot_4.3"
godot_executable="godot43.$DEVICE_ARCH"
weston_runtime="weston_pkg_0.2"

cd "$GAMEDIR"
mv -f "$GAMEDIR/log.txt" "$GAMEDIR/log.prev.txt" 2>/dev/null
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1
export PORT_REPORT_FILES="ports/domekeeper/log.txt and setup_log.txt"
source "$GAMEDIR/tools/portlog.sh"
port_header "Dome Keeper launcher"

# build/package.sh writes the same hash of the port folder's files here and into tools/files_version.
# A different value means this launcher and the folder come from different releases (a new launcher
# copied over an old folder, or the reverse), which fails in confusing ways, so ask for a reinstall.
port_files_version=9e46b6fa
files_version="$(cat "$GAMEDIR/tools/files_version" 2>/dev/null)"
if [ "$files_version" != "$port_files_version" ]; then
  port_log "port files version ${files_version:-missing}, the launcher expects $port_files_version: mixed install"
  pm_message "The launcher and the ports/domekeeper folder come from different versions of the port. Install the port again (domekeeper.pck can stay)."
  sleep 8
  pm_finish
  exit 1
fi
mkdir -p "$CONFDIR"

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

file_stamp() {
  if command -v stat >/dev/null; then stat -c '%s %Y' "$@" 2>/dev/null; return 0; fi
  local f
  for f in "$@"; do [ -e "$f" ] && echo "$(ls -lnL "$f" | awk '{print $5}') $(date -r "$f" +%s)"; done
  return 0
}
texture_factor="$(awk -v w="${DISPLAY_WIDTH:-640}" -v h="${DISPLAY_HEIGHT:-480}" 'BEGIN {
  s = w / 1920; if (h / 1080 < s) s = h / 1080
  z = 0.5 / s; if (z < 1) z = 1; if (z > 1.5) z = 1.5
  base = 4 * s; px = int(base * z + 0.5); if (px < base) px = int(base + 0.999); z = px / base
  f = int(1 / s + 0.5); if (f < 2) f = 2; if (f > 4) f = 4
  for (c = f; c >= 2; c--) { r = s * z * c; d = r - int(r + 0.5); if (d < 0) d = -d; if (d < 0.01) { f = c; break } }
  print f }')"
texture_astc=""
[ "$DEVICE_ARCH" = "aarch64" ] && [ -x "$controlfolder/astcenc.aarch64" ] && texture_astc="$controlfolder/astcenc.aarch64"
setup_version=4
# Under about 800 MB of RAM (a "1 GB" handheld whose firmware keeps part of it, MemTotal 662 MB on
# the G350) the game does not fit with the full size art: the setup then also loads sound effects
# only while they play and stores monster and effect sheets smaller. DK_LOWMEM=0 or 1 overrides.
mem_total_mb="$(awk '/^MemTotal:/ { print int($2 / 1024) }' /proc/meminfo 2>/dev/null)"
lowmem=0
[ "${mem_total_mb:-0}" -gt 0 ] && [ "${mem_total_mb:-0}" -lt 800 ] && lowmem=1
case "$DK_LOWMEM" in 0|1) lowmem="$DK_LOWMEM" ;; esac
port_log "memory profile: $([ "$lowmem" = 1 ] && echo "low memory" || echo normal) (${mem_total_mb:-unknown} MB of RAM)"
if [ "$lowmem" = 1 ] && [ "$(awk '/^SwapTotal:/ { print $2 }' /proc/meminfo 2>/dev/null)" = 0 ]; then
  port_log "warning: this device has no swap; with so little RAM the game may be closed by the system"
fi
lowmem_flag=""
[ "$lowmem" = 1 ] && lowmem_flag="lowmem"
texture_mode="$texture_factor ${texture_astc:+astc} setup$setup_version${lowmem_flag:+ $lowmem_flag}"
pck_stamp="$(file_stamp domekeeper.pck) $texture_mode"
port_files domekeeper.pck override.cfg
if [ ! -f override.cfg ] || [ "$(cat cache/.setup_stamp 2>/dev/null)" != "$pck_stamp" ]; then
  port_log "setup: needed (first run or game update; stamp '$(cat cache/.setup_stamp 2>/dev/null)', pck '$pck_stamp')"
else
  port_log "setup: up to date"
fi
if [ ! -f override.cfg ] || [ "$(cat cache/.setup_stamp 2>/dev/null)" != "$pck_stamp" ]; then
  export GAMEDIR godot_dir godot_executable DEVICE_ARCH controlfolder texture_factor texture_astc texture_mode lowmem_flag
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

grep -q "^run/flush_stdout_on_print" override.cfg 2>/dev/null ||
  printf '\n[application]\n\nrun/flush_stdout_on_print=true\n' >> override.cfg

half_res="$(awk -v w="${DISPLAY_WIDTH:-640}" -v h="${DISPLAY_HEIGHT:-480}" 'BEGIN {
  s = w / 1920; if (h / 1080 < s) s = h / 1080
  z = 0.5 / s; if (z < 1) z = 1; if (z > 1.5) z = 1.5
  base = 4 * s; px = int(base * z + 0.5); if (px < base) px = int(base + 0.999)
  print (px >= 2 && px % 2 == 0) ? "true" : "false" }')"
options_dir="$CONFDIR/godot/app_userdata/Dome Keeper"
if [ ! -f "$options_dir/options.txt" ]; then
  mkdir -p "$options_dir"
  echo '{"onlineMultiplayerDecided":true,"allowOnlineMultiplayer":false,"allowCrashReports":false,"fullscreen":true,"vsync":true,"targetfps":60,"singleplayerUseGamepad":true,"renderHalfRes":'"$half_res"'}' > "$options_dir/options.txt"
fi

mapping_pad() {
  local guid="${1%%,*}" name="${1#*,}" ev id pads=()
  name="${name%%,*}"
  le16() { local v=$((16#$(cat "$1" 2>/dev/null || echo 0))); printf '%02x%02x' $((v & 255)) $((v >> 8 & 255)); }
  for ev in /sys/class/input/event*/device; do
    [ -d "$ev/id" ] && ls -d "$ev"/js* >/dev/null 2>&1 || continue
    id="$(le16 "$ev/id/bustype")0000$(le16 "$ev/id/vendor")0000$(le16 "$ev/id/product")0000$(le16 "$ev/id/version")0000"
    [ "${id:0:4}${id:8}" = "${guid:0:4}${guid:8}" ] && { echo "$ev"; return; }
  done
  for ev in /sys/class/input/event*/device; do
    [ "$(cat "$ev/name" 2>/dev/null)" = "$name" ] && { echo "$ev"; return; }
  done
  for ev in /sys/class/input/event*/device; do
    ls -d "$ev"/js* >/dev/null 2>&1 || continue
    [ -n "$(cat "$ev/capabilities/key" 2>/dev/null)" ] && pads+=("$ev")
  done
  [ ${#pads[@]} -eq 1 ] && echo "${pads[0]}"
}
godot_joy_mapping() {
  local mapping="$1" name="${1#*,}" dev="" ev wbits=64 n i b w code
  name="${name%%,*}"
  dev="$(mapping_pad "$mapping")"
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

godot_mapping=""
pad_dev=""
# control.txt always fills sdl_controllerconfig; only some firmwares also export
# SDL_GAMECONTROLLERCONFIG (dArkOS does not). The list can hold several pads (Knulli puts an
# Xbox pad first), so take the line whose GUID matches a pad that is present, else the first line.
pad_guid_present() {
  local guid="${1%%,*}" ev id
  le16() { local v=$((16#$(cat "$1" 2>/dev/null || echo 0))); printf '%02x%02x' $((v & 255)) $((v >> 8 & 255)); }
  for ev in /sys/class/input/event*/device; do
    [ -d "$ev/id" ] && ls -d "$ev"/js* >/dev/null 2>&1 || continue
    id="$(le16 "$ev/id/bustype")0000$(le16 "$ev/id/vendor")0000$(le16 "$ev/id/product")0000$(le16 "$ev/id/version")0000"
    [ "${id:0:4}${id:8}" = "${guid:0:4}${guid:8}" ] && return 0
  done
  return 1
}
pad_mapping=""
first_mapping=""
while IFS= read -r line; do
  [[ "$line" =~ ^[0-9a-fA-F]{32}, ]] || continue
  [ -n "$first_mapping" ] || first_mapping="$line"
  if pad_guid_present "$line"; then pad_mapping="$line"; break; fi
done <<< "${sdl_controllerconfig}"$'\n'"${SDL_GAMECONTROLLERCONFIG}"
pad_mapping="${pad_mapping:-$first_mapping}"
while IFS= read -r line; do
  [ -n "$line" ] || continue
  godot_mapping="$(godot_joy_mapping "$line")"
  pad_dev="$(mapping_pad "$line")"
  break
done <<< "$pad_mapping"
godot_mapping="$(printf '%s' "$godot_mapping" | tr ' ' '.')"
pad_abs=$((16#$(awk '{print $NF}' "$pad_dev/capabilities/abs" 2>/dev/null || echo 0)))
if [ -n "$pad_dev" ] && ! (( (pad_abs & 3) == 3 || (pad_abs & 24) == 24 )) && [ -n "$GPTOKEYB2" ]; then
  port_log "controller: the built in pad has no axes Godot accepts (abs $(cat "$pad_dev/capabilities/abs")), using a virtual pad"
  $GPTOKEYB2 "$godot_executable" -x &
  godot_mapping="${godot_mapping%%,*},Ignored,misc1:h0.1,paddle1:h0.2,paddle2:h0.4,paddle3:h0.8,platform:Linux,"
elif [ "$CFW_NAME" = "muOS" ] && [ -n "$GPTOKEYB2" ]; then
  $GPTOKEYB2 "$godot_executable" -c "$GAMEDIR/domekeeper.gptk" &
else
  $GPTOKEYB "$godot_executable" -c "$GAMEDIR/domekeeper.gptk" &
fi
pm_platform_helper "$godot_dir/$godot_executable"
port_log "controller mapping for the game: ${godot_mapping:-none (Godot database)}"

port_memwatch_start "$godot_executable"
port_log "starting the game, UI scale ${DK_UI_SCALE:-automatic}, world zoom ${DK_WORLD_ZOOM:-automatic}, lobby zoom ${DK_LOBBY_ZOOM:-automatic}"
REAL_XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
$ESUDO env $weston_dir/westonwrap.sh headless noop kiosk crusty_x11egl \
  LD_PRELOAD= ${godot_mapping:+SDL_GAMECONTROLLERCONFIG="$godot_mapping"} XDG_DATA_HOME="$CONFDIR" XDG_RUNTIME_DIR="$REAL_XDG_RUNTIME_DIR" DK_UI_SCALE="${DK_UI_SCALE:-0}" DK_WORLD_ZOOM="${DK_WORLD_ZOOM:-0}" DK_LOBBY_ZOOM="${DK_LOBBY_ZOOM:-0}" DK_LOWMEM="$lowmem" \
  "$godot_dir/$godot_executable" --resolution "${DISPLAY_WIDTH}x${DISPLAY_HEIGHT}" -f \
  --rendering-driver opengl3_es --audio-driver ALSA --print-fps --main-pack "$GAMEDIR/domekeeper.pck"

port_exit
$ESUDO $weston_dir/westonwrap.sh cleanup
if [[ "$PM_CAN_MOUNT" != "N" ]]; then
  $ESUDO umount "$godot_dir"
  $ESUDO umount "$weston_dir"
fi
pm_finish
