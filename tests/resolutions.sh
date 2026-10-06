#!/bin/bash
# Screenshots at the common PortMaster resolutions: title, options panel, and the pause menu
# in a run started by devtools/autorun.gd. Output in tests/out/res-<WxH>/.
# Env: GODOT (run tests/prepare.sh first).
S="$(cd "$(dirname "$0")" && pwd)"
for RES in ${RESOLUTIONS:-640x480 480x320 720x720 854x480 1280x720 1920x1152}; do
  DISP=${DISP:-5} FRESH=1 "$S/localtest.sh" "$RES" "wait 20; shot title; tap dright; wait 1; press A; wait 3; shot options; press B; wait 2" "res-$RES-title"
  DISP=${DISP:-5} FRESH=1 AUTORUN=regular-small "$S/localtest.sh" "$RES" "wait 50; press A; wait 8; shot run; press START; wait 2; shot pause" "res-$RES-run"
done
