#!/bin/sh
# Runs ON the device. Every 2 s appends one line to <outfile> for <seconds>: MemAvailable, SwapFree,
# swap in/out pages and major page faults since the last line (a game that thrashes shows hundreds
# of major faults), the last "Project FPS" of the game's log and its resident and swapped memory.
# Usage: memsample.sh <outfile> <seconds> [game log] [game process pattern]
out=$1; n=$(( $2 / 2 ))
log=${3:-/userdata/roms/ports/domekeeper/log.txt}; pat=${4:-^/tmp/godot/godot43}
pi=$(awk '/^pswpin/{print $2}' /proc/vmstat); po=$(awk '/^pswpout/{print $2}' /proc/vmstat); pm=$(awk '/^pgmajfault/{print $2}' /proc/vmstat)
t0=$(date +%s); i=0
while [ $i -lt $n ]; do
  sleep 2; i=$((i+1))
  ni=$(awk '/^pswpin/{print $2}' /proc/vmstat); no=$(awk '/^pswpout/{print $2}' /proc/vmstat); nm=$(awk '/^pgmajfault/{print $2}' /proc/vmstat)
  p=$(pgrep -f "$pat" | tail -1)
  g=""; [ -n "$p" ] && g=$(awk '/VmRSS|VmSwap/{printf "%s%dMB ", $1, $2/1024}' /proc/$p/status)
  fps=$(grep -a "Project FPS" "$log" | tail -1 | awk '{print $3}')
  echo "t=$(( $(date +%s) - t0 )) avail=$(awk '/^MemAvailable/{print int($2/1024)}' /proc/meminfo) swapfree=$(awk '/^SwapFree/{print int($2/1024)}' /proc/meminfo) swin=$((ni-pi)) swout=$((no-po)) majflt=$((nm-pm)) fps=$fps $g" >> "$out"
  pi=$ni; po=$no; pm=$nm
done
