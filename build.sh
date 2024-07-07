#!/bin/sh

set -e

clang-format -i ./*.m ./*.metal

rm -rf build
mkdir -p build/MetalAsUI.app/Contents
mkdir build/MetalAsUI.app/Contents/MacOS
mkdir build/MetalAsUI.app/Contents/Resources

cp Info.plist build/MetalAsUI.app/Contents/Info.plist

clang -o build/MetalAsUI.app/Contents/MacOS/MetalAsUI \
	-fmodules -fobjc-arc \
	-g3 \
	-W \
	-Wall \
	-Wextra \
	-Wpedantic \
	-Wconversion \
	-Wimplicit-fallthrough \
	-Wmissing-prototypes \
	-Wshadow \
	-Wstrict-prototypes \
	main.m

xcrun metal \
	-o build/MetalAsUI.app/Contents/Resources/default.metallib \
	shaders.metal
