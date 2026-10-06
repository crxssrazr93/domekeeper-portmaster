#!/bin/bash
# Zips port/ into domekeeper.zip, laid out the way PortMaster's tools/build_release.py builds it
# (port.json, gameinfo.xml, screenshot.png and cover.png moved into the port folder, README.md
# renamed to domekeeper.md).
set -e
R="$(cd "$(dirname "$0")/.." && pwd)"
for a in aarch64 x86_64; do [ -x "$R/port/domekeeper/tools/godot_adpcm.$a" ] || { echo "run build/build.sh first"; exit 1; }; done
src="$R/port"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp "$src/Dome Keeper.sh" "$stage/"
cp -r "$src/domekeeper" "$stage/"
rm -rf "$stage"/domekeeper/*.pck "$stage/domekeeper/cache" "$stage/domekeeper/conf" "$stage/domekeeper/godot" \
  "$stage/domekeeper/override.cfg" "$stage/domekeeper/log.txt" "$stage/domekeeper/setup_log.txt" \
  "$stage/domekeeper/log.prev.txt" "$stage/domekeeper/setup_log.prev.txt"
cp "$src/port.json" "$src/gameinfo.xml" "$src/screenshot.png" "$src/cover.png" "$stage/domekeeper/"
cp "$src/README.md" "$stage/domekeeper/domekeeper.md"
rm -f "$R/domekeeper.zip"
(cd "$stage" && zip -9 -r -q -X "$R/domekeeper.zip" .)
ls -la "$R/domekeeper.zip"
