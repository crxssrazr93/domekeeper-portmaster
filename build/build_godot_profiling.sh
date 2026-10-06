#!/bin/bash
# Build Godot 4.3-stable x86_64 template_release WITH debug symbols, for memory profiling
# (same engine version/config as PortMaster's godot_4.3 runtime, but symbolized).
# Output: build/out/godot43-profiling.x86_64 (used by build/massif_gpu.sh)
set -e
cd "$(dirname "$0")"
mkdir -p src out
[ -d src/godot-4.3 ] || git clone -q --depth 1 --branch 4.3-stable https://github.com/godotengine/godot.git src/godot-4.3
docker run --rm -v "$PWD/src/godot-4.3:/src" -v "$PWD/out:/out" -w /src ubuntu:22.04 bash -c '
  set -e
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq >/dev/null
  apt-get install -y -qq build-essential scons pkg-config libx11-dev libxcursor-dev libxinerama-dev \
    libgl1-mesa-dev libglu1-mesa-dev libasound2-dev libpulse-dev libudev-dev libxi-dev libxrandr-dev \
    libwayland-dev >/dev/null
  scons -j"$(nproc)" platform=linuxbsd target=template_release arch=x86_64 debug_symbols=yes \
    production=yes lto=none 2>&1 | tail -3
  cp bin/godot.linuxbsd.template_release.x86_64 /out/godot43-profiling.x86_64
  chown '"$(id -u):$(id -g)"' /out/godot43-profiling.x86_64
'
ls -la out/godot43-profiling.x86_64
