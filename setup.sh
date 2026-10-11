#!/bin/bash
# ==============================================================================
# setup.sh - VecNIST development environment (Ubuntu 24.04 and later)
# ==============================================================================
# Installs / checks:
#   lwtools   6809 cross-assembler (lwasm), built into ./tools if it is not installed
#   mame      the emulator (machine "vectrex": needs the Vectrex BIOS, vectrex.zip, in ~/mame/roms)
#   python3 + numpy + Pillow + ffmpeg   training, the twin, screenshots and the demo video
#   Vide      optional: if found (VIDE_HOME, ../Vide.u32, /opt/vide/Vide.u64), build.sh also checks the source
#             with Vide's own assembler (needs java)
#   MNIST     only to retrain: weights.i is in the repository (get_mnist.sh)
# ==============================================================================
set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
LWTOOLS_VERSION="4.23"
echo "== VecNIST - environment setup =="
if command -v apt-get &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y build-essential wget mame python3 python3-numpy python3-pil ffmpeg default-jre-headless \
        || echo "   some packages failed - continuing"
else
    echo "   apt-get not found: install build-essential, mame, python3-numpy, python3-pil, ffmpeg yourself"
fi
echo "-- lwasm"
if ! command -v lwasm &> /dev/null; then
    mkdir -p tools/lwtools && cd tools/lwtools
    [ -f "lwtools-$LWTOOLS_VERSION.tar.gz" ] || wget -q "http://www.lwtools.ca/releases/lwtools/lwtools-$LWTOOLS_VERSION.tar.gz"
    tar xzf "lwtools-$LWTOOLS_VERSION.tar.gz"
    (cd "lwtools-$LWTOOLS_VERSION" && make -j"$(nproc)" && sudo make install)
    cd "$ROOT"
fi
echo "   $(command -v lwasm)"
echo "-- Vectrex BIOS for MAME"
if [ -f "$HOME/mame/roms/vectrex.zip" ] || [ -f /usr/share/games/mame/roms/vectrex.zip ]; then echo "   found vectrex.zip"
else echo "   MISSING vectrex.zip - put the Vectrex BIOS set (exec_rom.bin) in ~/mame/roms"; fi
echo "-- Vide (optional)"
for v in "$VIDE_HOME" "$ROOT/../Vide.u32" /opt/vide/Vide.u64; do
    [ -n "$v" ] && [ -f "$v/Vide.app/app/Vide.jar" ] && { echo "   found $v"; break; }
done
echo
echo "Next:  ./build.sh   then   ./run.sh"
