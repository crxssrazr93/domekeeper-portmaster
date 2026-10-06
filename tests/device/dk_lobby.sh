#!/bin/bash
# Restart Dome Keeper and walk into the singleplayer lobby (needs the PerfDiag autoload). Usage: dk_lobby.sh "<launcher path>"
curl -s localhost:1234/emukill; sleep 4; rm -f /tmp/perf.log
curl -s -d "${1:-/userdata/roms/ports/Dome Keeper.sh}" localhost:1234/launch
for i in $(seq 60); do sleep 2; tail -1 /tmp/perf.log 2>/dev/null | grep -q "shaders=11" && break; done
for try in 1 2 3 4 5 6; do
  python3 /userdata/system/devpad.py "wait 3; press B" > /dev/null
  for i in 1 2 3 4; do sleep 2; tail -1 /tmp/perf.log | grep -q "shaders=[4-9][0-9]" && { sleep 6; tail -1 /tmp/perf.log; exit 0; }; done
done
echo "lobby not reached"; exit 1
