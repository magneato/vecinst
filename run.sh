#!/bin/bash
# ==============================================================================
# run.sh - play VecNIST in MAME, or record the demo
# ==============================================================================
# The BIOS shows its own screen for about 10 seconds, then the title, then the game.
#   ./run.sh                     play: joystick = arrow keys or a gamepad; buttons 1-4 = MAME's P1 buttons
#   ./run.sh --pen               MAME's light pen on joystick port 1, aimed with the mouse
#   ./run.sh --video FILE.mp4    record the scripted demo (test/demo.py: a 1, a 7, a 0 and a 4, each read
#                                and cleared) frame-exact, then encode it with a phosphor-decay filter: MAME
#                                captures at 60 Hz what the Vectrex draws at 50, and a real vector tube glows
#   ./run.sh --no-build ...      skip the build
# Extra arguments go to MAME.
# ==============================================================================
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
BUILD=1; PEN=0; VIDEO=""
while [ $# -gt 0 ]; do
    case "$1" in
        --no-build) BUILD=0; shift ;;
        --pen)      PEN=1; shift ;;
        --video)    VIDEO="$2"; shift 2 ;;
        -h|--help)  sed -n 2,14p "$0"; exit 0 ;;
        *) break ;;
    esac
done
[ "$BUILD" = 1 ] && { ./build.sh || exit 1; }
ROMPATH="${MAME_ROMPATH:-$HOME/mame/roms;/usr/share/games/mame/roms}"
CART="$ROOT/build/vecnist.bin"; [ -s "$CART" ] || CART="$ROOT/rom/vecnist.bin"

if [ -z "$VIDEO" ]; then
    ARGS=()
    [ "$PEN" = 1 ] && ARGS+=(-lightgun -lightgun_device mouse)
    exec mame vectrex -rompath "$ROMPATH" -cart "$CART" -window -nomaximize -skip_gameinfo "${ARGS[@]}" "$@"
fi

# --- the demo recording
eval "$(python3 test/demo.py | sed -n '1,3p' | sed 's/^/export /')"
FIRST=600                                         # the cartridge's title is up by then (the BIOS intro is skipped)
RAW="$ROOT/build/demo_raw.avi"
rm -f "$RAW"
STICK="$STICK" BTN="$BTN" EXITAT=$((END + 60)) TIMEOUT=900 CART="$CART" \
    test/mv.sh -aviwrite "$RAW" -snapsize 768x1024 -sound auto "$@" > /dev/null
[ -s "$RAW" ] || { echo "run.sh: MAME wrote no recording"; exit 1; }
ffmpeg -y -loglevel error -ss "$(python3 -c "print($FIRST/60)")" -i "$RAW" \
    -vf "lagfun=decay=0.82,format=gbrp,split[a][b];[b]gblur=sigma=4[g];[a][g]blend=all_mode=screen,eq=contrast=1.35:brightness=0.03:gamma=1.25,format=yuv420p" \
    -c:v libx264 -crf 18 -preset slow -r 60 -c:a aac -b:a 128k -movflags +faststart "$VIDEO" \
    && echo "run.sh: wrote $VIDEO ($(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VIDEO" | cut -c1-5) s)"
