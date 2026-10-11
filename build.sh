#!/bin/bash
# build.sh - build the VecNIST cartridge.
#   1. weights.i: trained on the PC (train/vecnist.py) if it is missing (it is committed, so normally it is there)
#   2. lwasm assembles vecnist.asm -> build/vecnist.bin (+ listing and symbols)
#   3. if Vide is installed, Vide's own assembler assembles the same source (as the IDE does: vecnist.bin beside it)
#      and the two binaries must be identical
# VIDE_HOME (default: ../Vide.u32 or /opt/vide/Vide.u64) points at Vide; set NO_VIDE=1 to skip step 3.
# The ROM is also copied to rom/vecnist.bin, the copy the web page offers for download.
set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
mkdir -p build
if [ ! -s weights.i ]; then
    [ -s data/TRAIN.IDX ] || ./get_mnist.sh
    python3 train/vecnist.py train
fi
lwasm --6809 --format=raw --list=build/vecnist.lst --symbol-dump=build/vecnist.sym -o build/vecnist.bin vecnist.asm
echo "  build/vecnist.bin: $(stat -c%s build/vecnist.bin) bytes (lwasm)"
mkdir -p rom
cp build/vecnist.bin rom/vecnist.bin                          # the published copy (index.html links it)
if [ -z "$NO_VIDE" ]; then
    for v in "$VIDE_HOME" "$ROOT/../Vide.u32" /opt/vide/Vide.u64; do
        [ -n "$v" ] && [ -f "$v/Vide.app/app/Vide.jar" ] && { VIDE="$(cd "$v" && pwd)"; break; }
    done
    if [ -n "$VIDE" ]; then
        JAR="$VIDE/Vide.app/app/Vide.jar"
        mkdir -p build/vide
        [ build/vide/VideAsm.class -nt tools/VideAsm.java ] || javac -cp "$JAR" -d build/vide tools/VideAsm.java 2>/dev/null
        VIDE_HOME="$VIDE" java -Djava.awt.headless=true --enable-native-access=ALL-UNNAMED -cp "$JAR:build/vide" \
            VideAsm "$ROOT/vecnist.asm" build/vecnist_vide.lst 2>&1 | grep -v -E '^WARNING|^\+\+\+\+\+\+|^       /' || true
        cmp vecnist.bin build/vecnist.bin && echo "  Vide's assembler: identical bytes" \
            || { echo "  Vide's assembler built different bytes"; exit 1; }
    else
        echo "  (Vide not found: skipped the Vide assembler check)"
    fi
fi
