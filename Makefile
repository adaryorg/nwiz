.PHONY: build clean

build:
	zig build -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSafe
	strip zig-out/bin/nwiz
	mv zig-out/bin/nwiz zig-out/bin/nwiz-linux-x86_64
	zig build -Dtarget=x86_64-macos -Doptimize=ReleaseSafe
	mv zig-out/bin/nwiz zig-out/bin/nwiz-macos-x86_64
	zig build -Dtarget=aarch64-macos -Doptimize=ReleaseSafe
	mv zig-out/bin/nwiz zig-out/bin/nwiz-macos-aarch64

clean:
	rm -f zig-out/bin/nwiz*