#!/bin/bash
# Local device-like test of Dome Keeper on the PortMaster x86_64 Godot 4.3 runtime:
# an offscreen Xvfb server (no window on the desktop) at a handheld resolution, scripted virtual gamepad, RSS sampling.
# Usage: localtest.sh <WxH> "<vpad script>" [tag] [godot binary]   (run tests/prepare.sh first)
# Env: GODOT, DISP (X display number, default 5), FRESH=1 (fresh user data), AUTORUN=<map archetype, e.g. regular-small> and
# AUTORUN_ARGS (devtools/autorun.gd starts a run by itself), TEXDUMP_AFTER (seconds).
set -u
ulimit -c 0  # no core dumps, so a forced stop never reaches the desktop crash reporter
S="$(cd "$(dirname "$0")" && pwd)"; G="$S/out/game"
RES="${1:-640x480}"; SCRIPT="$2"; TAG="${3:-run}"
GODOT="${4:-${GODOT:?set GODOT to godot43.x86_64}}"; G="${GAMEDIR:-$G}"; PCK="${PCK:-domekeeper.pck}"
OUT="$S/out/$TAG"; mkdir -p "$OUT"; rm -f "$OUT"/*.png "$OUT"/*.mp4 "$OUT"/diag.log "$OUT"/rss.log
# a previous server on this display may still be shutting down; then wait until the new one answers
while [ -e "/tmp/.X${DISP:-5}-lock" ]; do sleep 0.5; done
unset WAYLAND_DISPLAY; Xvfb :${DISP:-5} -screen 0 "$RES"x24 -nolisten tcp >/dev/null 2>&1 & XPID=$!
for i in $(seq 40); do DISPLAY=:${DISP:-5} xdpyinfo >/dev/null 2>&1 && break; sleep 0.5; done
before=$(ls /dev/input/)
REC_CMD="ffmpeg -y -loglevel error -f x11grab -framerate 30 -video_size $RES -i :${DISP:-5} -c:v libx264 -preset ultrafast $OUT/{name}.mp4" \
SHOT_CMD="DISPLAY=:${DISP:-5} import -window root $OUT/{name}.png 2>/dev/null" \
  python3 "$S/vpad.py" "wait 2; $SCRIPT" & VPID=$!
sleep 2
new=$(comm -13 <(echo "$before" | sort) <(ls /dev/input/ | sort))
binds=(); for n in $new; do binds+=(--dev-bind "/dev/input/$n" "/dev/input/$n"); done
cd "$G"
# isolated user data (like PortMaster's XDG_DATA_HOME=$GAMEDIR/conf); FRESH=1 starts from nothing
export AUTORUN_LOG="$OUT/autorun.log"
export XDG_DATA_HOME="${XDG_HOME:-$S/out/home-$TAG}"; [ "${FRESH:-0}" = 1 ] && rm -rf "$XDG_DATA_HOME"; mkdir -p "$XDG_DATA_HOME"
# same first-start options the launcher writes (offline, fullscreen, gamepad)
O="$XDG_DATA_HOME/godot/app_userdata/Dome Keeper"; mkdir -p "$O"
[ -f "$O/options.txt" ] || echo '{"onlineMultiplayerDecided":true,"allowOnlineMultiplayer":false,"allowCrashReports":false,"fullscreen":true,"vsync":true,"targetfps":60,"singleplayerUseGamepad":true}' > "$O/options.txt"
DISPLAY=:${DISP:-5} bwrap --die-with-parent --dev-bind / / --tmpfs /dev/input "${binds[@]}" \
  "$GODOT" --main-pack "$PCK" --resolution "$RES" --position 0,0 -- --diag="$OUT/diag.log" --texdump="$OUT/textures.txt" ${AUTORUN:+--autorun=$AUTORUN} ${AUTORUN_ARGS:-} \
  > "$OUT/game.log" 2>&1 & GPID=$!
( while kill -0 $GPID 2>/dev/null; do
    P=$(pgrep -P $GPID -f "main-pack" || true)
    [ -n "$P" ] && awk -v t="$SECONDS" '/VmRSS/{r=$2}/VmSwap/{s=$2}/VmHWM/{h=$2}END{print t"s rss+swap="int((r+s)/1024)"MB rss="int(r/1024)"MB hwm="int(h/1024)"MB"}' /proc/$P/status 2>/dev/null
    sleep 3; done > "$OUT/rss.log" ) &
wait $VPID
P=$(pgrep -P $GPID -f "main-pack")
PEAK=$(awk '/VmHWM/{print int($2/1024)}' /proc/$P/status 2>/dev/null)
ALIVE=$(kill -0 $GPID 2>/dev/null && echo yes || echo no)
# stop Godot itself first and wait for it, only then Xwayland (Godot dies on a lost X connection)
[ -n "$P" ] && kill $P 2>/dev/null; for i in $(seq 20); do kill -0 $GPID 2>/dev/null || break; sleep 0.5; done
kill -9 $GPID $P 2>/dev/null; wait $GPID 2>/dev/null; kill $XPID 2>/dev/null; wait $XPID 2>/dev/null
echo "alive=$ALIVE peakRSS=${PEAK}MB files: $(ls "$OUT" | grep -E 'png|mp4' | tr '\n' ' ')"
tail -2 "$OUT/diag.log" 2>/dev/null
