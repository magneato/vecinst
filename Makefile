# Thin wrapper - the real work is in ./build.sh, train/vecnist.py and test/run_tests.sh
all:
	./build.sh
video: all
	./run.sh --no-build --video vecinst.mp4
train:
	./get_mnist.sh
	python3 train/vecnist.py train
run: all
	./run.sh --no-build
test: all
	test/run_tests.sh
clean:
	rm -rf build vecnist.bin vecnist.cnt
.PHONY: all train run video test clean
