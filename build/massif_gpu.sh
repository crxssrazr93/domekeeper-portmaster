#!/bin/bash
# Heap profile of Dome Keeper on the symbolized Godot build with the real GLES3 renderer:
# valgrind massif inside Ubuntu 22.04 (host ld.so is built for newer CPUs than valgrind
# handles), host GPU via /dev/dri, drawing to a host Xwayland display.
# Usage: massif_gpu.sh <tag> <quit-after-frames> [WxH]   (needs build/build_godot_profiling.sh and tests/prepare.sh)
# Env: AUTORUN=<map archetype> starts a run. Read the result with ms_print tests/out/massif/massif-<tag>.out.
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"; G="$R/tests/out/game"; TAG="$1"; FRAMES="$2"; RES="${3:-640x480}"
OUT="$R/tests/out/massif"; mkdir -p "$OUT"
# snapshot of the port scripts, so edits made while this runs do not leak into the profile
SNAP="$OUT/snap-$TAG"; rm -rf "$SNAP"; mkdir -p "$SNAP"; cp -r "$G/stubs" "$G/devtools" "$G/override.cfg" "$SNAP/"
Xwayland :7 -ac -geometry "$RES" -decorate >/dev/null 2>&1 & XPID=$!
sleep 2
docker rm -f dkmassif-gpu >/dev/null 2>&1
docker run --rm --name dkmassif-gpu --ulimit core=0 --device /dev/dri -e DISPLAY=:7 \
  -v /tmp/.X11-unix:/tmp/.X11-unix -v /run/udev:/run/udev:ro -v "$G:/game" -v "$SNAP/stubs:/game/stubs:ro" -v "$SNAP/devtools:/game/devtools:ro" -v "$SNAP/override.cfg:/game/override.cfg:ro" -v "$R/build/out:/bin2:ro" -v "$OUT:/out" \
  -e XDG_DATA_HOME=/out/home-$TAG -e AUTORUN ubuntu:22.04 bash -c "apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq valgrind libfontconfig1 libgl1 libgl1-mesa-dri libxcursor1 libxinerama1 libxrandr2 libxi6 libxext6 libasound2 libpulse0 libudev1 udev >/dev/null 2>&1; cd /game && valgrind --tool=massif --threshold=0.5 --depth=40 --max-snapshots=60 --massif-out-file=/out/massif-$TAG.out /bin2/godot43-profiling.x86_64 --main-pack domekeeper.pck --resolution $RES --position 0,0 --audio-driver Dummy --quit-after $FRAMES -- ${AUTORUN:+--autorun=$AUTORUN} > /out/run-$TAG.log 2>&1; echo exit=\$? >> /out/run-$TAG.log"
kill $XPID 2>/dev/null
