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
# Release zips carry the "# PORTMASTER:" line that PortMaster's own build adds; without it
# harbourmaster inserts it into the launcher on its first runtime download, even while it runs.
{ head -n 1 "$src/Dome Keeper.sh"; echo "# PORTMASTER: domekeeper.zip, Dome Keeper.sh"; tail -n +2 "$src/Dome Keeper.sh"; } > "$stage/Dome Keeper.sh"
chmod 755 "$stage/Dome Keeper.sh"
cp -r "$src/domekeeper" "$stage/"
rm -rf "$stage"/domekeeper/*.pck "$stage/domekeeper/cache" "$stage/domekeeper/conf" "$stage/domekeeper/godot" \
  "$stage/domekeeper/override.cfg" "$stage/domekeeper/log.txt" "$stage/domekeeper/setup_log.txt" \
  "$stage/domekeeper/log.prev.txt" "$stage/domekeeper/setup_log.prev.txt"
# Stamp the launcher and tools/files_version with a hash of everything the port folder ships, so the
# launcher can tell when it runs against files from another release. Both stamps are committed.
files_version=$(cd "$stage/domekeeper" && find . -type f ! -path ./tools/files_version | LC_ALL=C sort |
  xargs -d '\n' md5sum | md5sum | cut -c1-8)
echo "$files_version" | tee "$src/domekeeper/tools/files_version" > "$stage/domekeeper/tools/files_version"
sed -i "s/^port_files_version=.*/port_files_version=$files_version/" "$src/Dome Keeper.sh" "$stage/Dome Keeper.sh"
cp "$src/port.json" "$src/gameinfo.xml" "$src/screenshot.png" "$src/cover.png" "$stage/domekeeper/"
cp "$src/README.md" "$stage/domekeeper/domekeeper.md"
rm -f "$R/domekeeper.zip"
(cd "$stage" && zip -9 -r -q -X "$R/domekeeper.zip" .)
ls -la "$R/domekeeper.zip"
