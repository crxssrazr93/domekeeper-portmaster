#!/bin/bash
# Run the real Dome Keeper launcher on this PC against a mock PortMaster install:
# control.txt, mount/umount (symlinks: godot_4.3 -> the x86_64 runtime, weston -> a stand-in
# that starts Xwayland), DEVICE_ARCH=x86_64. Exercises the first-run setup end to end.
# Usage: launchertest.sh "<vpad script>" [tag]     (FRESH=1 starts from an untouched pck)
# Env: GAME_PCK, GODOT (the x86_64 godot_4.3 runtime binary; its folder stands in for the mount),
# RES_W/RES_H (default 640x480), DISP. Needs build/build.sh to have run.
set -u
ulimit -c 0
S="$(cd "$(dirname "$0")" && pwd)"; R="$S/.."
: "${GAME_PCK:?set GAME_PCK to your domekeeper.pck}"; : "${GODOT:?set GODOT to godot43.x86_64}"; RT="$(dirname "$GODOT")"
SCRIPT="$1"; TAG="${2:-launcher}"
ROOT="$S/out/mockroot"; OUT="$S/out/$TAG"; mkdir -p "$OUT"; rm -f "$OUT"/*.mp4 "$OUT"/*.png
G="$ROOT/ports/domekeeper"
if [ "${FRESH:-0}" = 1 ] || [ ! -d "$G" ]; then
  rm -rf "$ROOT"; mkdir -p "$ROOT/ports" "$ROOT/PortMaster/libs" "$ROOT/bin" "$ROOT/weston"
  cp -r "$R/port/." "$ROOT/ports/"
  cp "$GAME_PCK" "$G/"
else
  cp -r "$R/port/." "$ROOT/ports/"   # refresh port files, keep pck, cache and saves
fi
touch "$ROOT/PortMaster/libs/weston_pkg_0.2.squashfs" "$ROOT/PortMaster/libs/godot_4.3.squashfs"
cat > "$ROOT/PortMaster/control.txt" <<EOC
directory="${ROOT#/}"; ESUDO=""; GPTOKEYB="true"; GPTOKEYB2="true"; CFW_NAME="mock"; PM_CAN_MOUNT="Y"; DEVICE_ARCH="x86_64"
DISPLAY_WIDTH=${RES_W:-640}; DISPLAY_HEIGHT=${RES_H:-480}
get_controls() { :; }; pm_message() { echo "PM_MESSAGE: \$*"; }; pm_finish() { echo PM_FINISH; }; pm_platform_helper() { :; }
EOC
# PortMaster's patcher (a LÖVE screen that runs PATCHER_FILE and shows its output) as plain output
mkdir -p "$ROOT/PortMaster/utils"
printf '"$PATCHER_FILE" | sed "s/^/PATCHER: /"\n' > "$ROOT/PortMaster/utils/patcher.txt"
cat > "$ROOT/bin/mount" <<EOM
#!/bin/bash
case "\$1" in *godot_4.3*) src="$RT";; *) src="$ROOT/weston";; esac
rmdir "\$2" 2>/dev/null; rm -f "\$2"; ln -s "\$src" "\$2"
EOM
printf '#!/bin/bash\nfor a in "$@"; do [ -L "$a" ] && rm -f "$a"; done; exit 0\n' > "$ROOT/bin/umount"
cat > "$ROOT/weston/westonwrap.sh" <<EOW
#!/bin/bash
[ "\$1" = cleanup ] && { echo WESTON_CLEANUP; exit 0; }
echo "WESTONWRAP args: \$1 \$2 \$3 \$4"; shift 4
unset WAYLAND_DISPLAY; export SDL_VIDEODRIVER=x11 XDG_RUNTIME_DIR=/tmp/xdg-offscreen; mkdir -p -m 700 /tmp/xdg-offscreen; Xvfb :${DISP:-5} -screen 0 ${RES_W:-640}x${RES_H:-480}x24 -nolisten tcp >/dev/null 2>&1 & XP=\$!; sleep 2
DISPLAY=:${DISP:-5} env "\$@" & GP=\$!
wait \$GP; kill \$XP
EOW
chmod +x "$ROOT"/bin/* "$ROOT/weston/westonwrap.sh"
( export PATH="$ROOT/bin:$PATH" XDG_DATA_HOME="$ROOT/xdg"; mkdir -p "$ROOT/xdg"; ln -sfn "$ROOT/PortMaster" "$ROOT/xdg/PortMaster"
  bash "$ROOT/ports/Dome Keeper.sh" ) > "$OUT/launcher.out" 2>&1 & LP=$!
# wait until the game window is up (after any first-run setup), then drive it
for i in $(seq 1800); do pgrep -f "main-pack $G/domekeeper.pck" >/dev/null && break; kill -0 $LP 2>/dev/null || break; sleep 1; done
sleep 3
REC_CMD="ffmpeg -y -loglevel error -f x11grab -framerate 30 -video_size ${RES_W:-640}x${RES_H:-480} -i :${DISP:-5} -c:v libx264 -preset ultrafast $OUT/{name}.mp4" \
SHOT_CMD="DISPLAY=:${DISP:-5} import -window root $OUT/{name}.png 2>/dev/null" python3 "$S/vpad.py" "$SCRIPT" > /dev/null
P=$(pgrep -f "main-pack $G/domekeeper.pck" | tail -1)
[ -n "$P" ] && awk '/VmRSS/{r=$2}/VmSwap/{s=$2}/VmHWM/{h=$2}END{print "game rss+swap="int((r+s)/1024)"MB hwm="int(h/1024)"MB"}' /proc/$P/status
[ -n "$P" ] && kill $P; wait $LP
echo "--- launcher output"; grep -E "PM_|WESTON|PORT_SETUP: (OK|[a-zA-Z ]*[=:])" "$OUT/launcher.out"
# setup prints compile errors while it repacks the title scene (harmless, see docs/PORTING.md); count only the game's
awk '/PORT_SETUP: OK/{f=1} f&&/SCRIPT ERROR/{c++} END{print "script errors after setup: " c+0}' "$OUT/launcher.out"
