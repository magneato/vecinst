#!/bin/bash
# test/mv.sh - run the cartridge in MAME driven by test/harness.lua (see its header for the variables)
#   SHOTS="300" BTN="200-260:1" STICK="200-260:255:128" EXITAT=320 test/mv.sh [extra mame args]
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNAP="${SNAPDIR:-$ROOT/build/snap}"
rm -rf "$SNAP"; mkdir -p "$SNAP"
timeout -s KILL "${TIMEOUT:-300}" mame vectrex -rompath "$HOME/mame/roms;/usr/share/games/mame/roms" \
    -cart "${CART:-$ROOT/build/vecnist.bin}" -video soft -window -nomaximize -sound none ${NOTHR:--nothrottle} \
    -skip_gameinfo -snapshot_directory "$SNAP" -autoboot_script "$ROOT/test/harness.lua" "$@" 2>&1 \
    | grep -E "SHOT|ANS|GRID|BATCH|PEEK|LPENDBG|rror|ERR" || true
ls "$SNAP/vectrex" 2>/dev/null || true
