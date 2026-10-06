#!/bin/bash
# Builds the IMA ADPCM sample encoder for aarch64 and x86_64 (static) into port/domekeeper/tools/.
set -e
R="$(cd "$(dirname "$0")/.." && pwd)"
docker build -q -t domekeeper-pm-build "$R/build" >/dev/null
docker run --rm -u "$(id -u):$(id -g)" -v "$R:/src" domekeeper-pm-build bash -c '
  set -e
  mkdir -p port/domekeeper/tools
  gcc -O2 -static -o port/domekeeper/tools/godot_adpcm.x86_64 src/godot_adpcm/godot_adpcm.c -lm
  aarch64-linux-gnu-gcc -O2 -static -o port/domekeeper/tools/godot_adpcm.aarch64 src/godot_adpcm/godot_adpcm.c -lm
'
ls -la "$R/port/domekeeper/tools/"
