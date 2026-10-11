#!/bin/bash
# get_mnist.sh - put MNIST (the classic 70,000 handwritten digits) into data/ for training.
#   data/TRAIN.IDX  TRAINL.IDX   60,000 training images and their labels
#   data/TEST.IDX   TESTL.IDX    10,000 test images and their labels
# Copies a local copy if one is known (MNIST_SRC, or the CoCo 3 nsx6809 project beside this one), else downloads.
# MNIST is Yann LeCun, Corinna Cortes and Christopher J.C. Burges' work: it is not part of this repository.
set -e
cd "$(dirname "${BASH_SOURCE[0]}")"
mkdir -p data
LOCAL="${MNIST_SRC:-../coco3/nsx6809/data}"
MIRRORS="https://ossci-datasets.s3.amazonaws.com/mnist https://storage.googleapis.com/cvdf-datasets/mnist http://yann.lecun.com/exdb/mnist"
fetch() {   # remote name, local name
    [ -s "data/$2" ] && { echo "  data/$2 already here"; return 0; }
    [ -s "$LOCAL/$2" ] && { cp "$LOCAL/$2" "data/$2"; echo "  data/$2 copied from $LOCAL"; return 0; }
    for m in $MIRRORS; do
        if curl -fsSL "$m/$1" -o "data/$1" 2>/dev/null; then
            gunzip -c "data/$1" > "data/$2" && rm -f "data/$1"
            echo "  data/$2  ($(wc -c < "data/$2") bytes)"
            return 0
        fi
    done
    echo "  could not get $1"; return 1
}
fetch train-images-idx3-ubyte.gz TRAIN.IDX
fetch train-labels-idx1-ubyte.gz TRAINL.IDX
fetch t10k-images-idx3-ubyte.gz  TEST.IDX
fetch t10k-labels-idx1-ubyte.gz  TESTL.IDX
