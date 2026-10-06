#!/bin/bash
# Prepares tests/out/game: a copy of your domekeeper.pck with the port files and the first-run
# setup applied (what the launcher does on a device), plus the test devtools autoloads.
# Env: GAME_PCK (your domekeeper.pck), GODOT (PortMaster godot_4.3 runtime, x86_64 build).
# Re-run with FRESH=1 to start again from an untouched pck.
set -eu
R="$(cd "$(dirname "$0")/.." && pwd)"; G="$R/tests/out/game"
: "${GAME_PCK:?set GAME_PCK to your domekeeper.pck}"; : "${GODOT:?set GODOT to godot43.x86_64 from the godot_4.3 runtime}"
[ -x "$R/port/domekeeper/tools/godot_adpcm.x86_64" ] || { echo "run build/build.sh first"; exit 1; }
[ "${FRESH:-0}" = 1 ] && rm -rf "$G"
mkdir -p "$G"
cp -r "$R/port/domekeeper/stubs" "$R/port/domekeeper/setup" "$R/port/domekeeper/tools" "$G/"
rm -rf "$G/devtools"; cp -r "$R/tests/devtools" "$G/devtools"
if [ ! -f "$G/override.cfg" ]; then
  cp "$GAME_PCK" "$G/domekeeper.pck"
  ( cd "$G" && time "$GODOT" --headless --main-pack domekeeper.pck --script res://setup/port_setup.gd -- \
      --out="$G" --encoder="$G/tools/godot_adpcm.x86_64" ) 2>&1 | grep -E "PORT_SETUP|ERROR|real" | grep -v "converted$\|scaled$"
  cp "$G/override.cfg" "$G/override.cfg.clean"
fi
# devtools autoloads ahead of the port's stubs (test only, never shipped)
sed '/^\[autoload\]/a\
\
PortDiag="*res://devtools/diag.gd"\
PortAutorun="*res://devtools/autorun.gd"' "$G/override.cfg.clean" > "$G/override.cfg"
echo "prepared $G"
