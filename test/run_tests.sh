#!/bin/bash
# test/run_tests.sh - everything that can be checked without a person at the controls.
#   1. self-tests: the training pipeline (batched) equals the per-drawing twin of the 6809's rasteriser
#   2. build: lwasm, and Vide's own assembler must produce the same bytes
#   3. the gate: 400 drawings through the cartridge in MAME, answers, scores and grids byte for byte = the twin
#   4. drawn with the (scripted) joystick: a 1, a 7 and a 0 must be read as 1, 7 and 0; screenshots saved
#   5. light pen: pen mode runs (MAME's pen emulation is not a faithful pen, see README)
set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p screenshots
echo "== 1. self-tests"
python3 train/vecnist.py selftest
echo "== 2. build"
./build.sh
[ -s build/model.npz ] || python3 train/vecnist.py train
echo "== 3. the cartridge against its twin"
python3 test/twin_test.py
echo "== 4. drawn with the joystick"
draw() {   # name expected STICK BTN end
    local name=$1 want=$2 stick=$3 btn=$4 end=$5
    local got
    got=$(STICK="$stick" BTN="$btn" SHOTS="$((end+30)) $((end+31)) $((end+32)) $((end+33))" PEEK="$((end+30)):C88A:1" \
          EXITAT=$((end+34)) test/mv.sh | sed -n 's/^PEEK [0-9]* C88A //p')
    python3 test/shot.py "screenshots/$name.png" build/snap/vectrex/000{0,1,2,3}.png
    if [ "$((16#$got))" = "$want" ]; then echo "   $name: read as $want"; else echo "   $name: read as $((16#$got)), wanted $want"; return 1; fi
}
draw drawn_1 1 "850-880:128:0" "850-880:1" 880
draw drawn_7 7 "860-874:0:255,880-899:255:128,900-926:82:0" "880-926:1" 926
draw drawn_0 0 "860-873:128:255,876-882:0:0,883-891:128:0,892-898:255:0,899-905:255:255,906-914:128:255,915-921:0:255,922-923:0:0" "876-923:1" 923
echo "== 5. light pen mode runs"
out=$(LPENCONF=1 BTN="850-852:4" LPEN="860-940:-48:-16:-60:10" PEEK="900:C8AB:1,950:C8AB:1,950:C886:1" EXITAT=951 test/mv.sh -video none | grep PEEK)
f1=$(echo "$out" | sed -n '1s/.* //p'); f2=$(echo "$out" | sed -n '2s/.* //p'); m=$(echo "$out" | sed -n '3s/.* //p')
[ "$m" = "01" ] && [ "$f1" != "$f2" ] && echo "   pen mode on, frames running" || { echo "   pen mode did not run"; exit 1; }
echo "== all tests passed"
