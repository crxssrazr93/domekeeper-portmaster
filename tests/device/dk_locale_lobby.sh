#!/bin/sh
# Runs ON the device. Measures the lobby in one language on a G350-sized memory budget: clears
# swap, mlocks RAM until about <avail MB> is left (ballast.py), sets the game's language in
# options.txt, starts Dome Keeper with user://autorun.txt = lobby (tests/devtools/autorun.gd must be
# an autoload) and samples every 2 s for <seconds> once the lobby stage has started.
# Usage: [SHOT=<raw file>] dk_locale_lobby.sh <locale> <out file> [seconds] [avail MB]
loc=$1; out=$2; secs=${3:-150}; target=${4:-440}
ports=/userdata/roms/ports; dk=$ports/domekeeper; ud="$dk/conf/godot/app_userdata/Dome Keeper"
curl -s localhost:1234/emukill > /dev/null; sleep 5
# the game writes options.txt (with its current language) as it exits: wait until it is gone
for i in $(seq 30); do pgrep -f '[g]odot43' > /dev/null || break; sleep 1; done
pkill -9 -f '[g]odot43' 2>/dev/null; pkill -f '[b]allast.py' 2>/dev/null; sleep 2
swapoff /dev/zram0 && swapon -p 1000 /dev/zram0
echo lobby > "$ud/autorun.txt"
sed -i "s/\"locale\":\"[a-zA-Z_]*\"/\"locale\":\"$loc\"/" "$ud/options.txt"
avail=$(awk '/^MemAvailable/{print int($2/1024)}' /proc/meminfo)
python3 /userdata/system/ballast.py $((avail - target)) > /dev/null &
sleep 8
: > "$out"; rm -f "$ud/autorun.log"
echo "locale=$loc start: $(awk '/^(MemAvailable|SwapFree):/{printf "%s %d MB ", $1, $2/1024}' /proc/meminfo)" >> "$out"
curl -s -d "$ports/Dome Keeper.sh" localhost:1234/launch > /dev/null
for i in $(seq 90); do sleep 2; grep -aq 'Start Stage: stages/loadout' "$dk/log.txt" 2>/dev/null && break; done
grep -aq 'Start Stage: stages/loadout' "$dk/log.txt" || echo "lobby not reached" >> "$out"
grep -a 'locale' "$dk/log.txt" | tail -1 >> "$out"
# SHOT=<file>: a raw framebuffer dump 25 s into the lobby (convert like tests/device/knulli_shot.sh)
[ -n "$SHOT" ] && { sleep 25; cat /sys/class/graphics/fb0/virtual_size /sys/class/graphics/fb0/pan > "$SHOT.info"; dd if=/dev/fb0 of="$SHOT" bs=1M 2>/dev/null; }
sh /userdata/system/memsample.sh "$out" "$secs"
grep -a '^PORT: .*mem:' "$dk/log.txt" >> "$out"
cat "$ud/autorun.log" >> "$out" 2>/dev/null
curl -s localhost:1234/emukill > /dev/null; sleep 5
pkill -f '[b]allast.py'
