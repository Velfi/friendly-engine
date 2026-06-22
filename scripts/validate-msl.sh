#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: validate-msl.sh <source.msl> <output.air>" >&2
    exit 2
fi

source_file=$1
output_file=$2
output_dir=$(dirname "$output_file")
cache_dir=${TMPDIR:-/tmp}/friendly-engine-metal-cache

mkdir -p "$output_dir"
mkdir -p "$cache_dir"

toolchain_path=$(xcodebuild -showComponent MetalToolchain 2>/dev/null | sed -n 's/^Toolchain Search Path: //p')
if [ -n "$toolchain_path" ] && [ -x "$toolchain_path/Metal.xctoolchain/usr/bin/metal" ]; then
    metal_bin="$toolchain_path/Metal.xctoolchain/usr/bin/metal"
else
    metal_bin=$(xcrun -find metal)
fi

"$metal_bin" \
    -x metal \
    -fmodules-cache-path="$cache_dir" \
    -c "$source_file" \
    -o "$output_file"
