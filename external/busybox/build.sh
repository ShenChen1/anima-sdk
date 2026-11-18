#!/bin/bash
set -euo pipefail

[ "$#" = 1 ] || { echo "Usage: $0 OUTPUT_DIRECTORY" >&2; exit 1; }
recipe=$(dirname "$(realpath "$0")")
sdk=$(realpath "$recipe/../..")
output=$(realpath -m "$1")
prefix=${CROSS_COMPILE:-$sdk/prebuilts/gcc/linux-x86/aarch64/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-}
target=$("${prefix}gcc" -dumpmachine)
case "$target" in aarch64*-linux-gnu*) ;; *) echo "Expected an AArch64 Linux compiler" >&2; exit 1 ;; esac
jobs=${JOBS:-$(nproc)}
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid JOBS" >&2; exit 1; }
export LC_ALL=C TZ=UTC KCONFIG_NOTIMESTAMP=1
mkdir -p "$output"
work=$(mktemp -d "$output/work.XXXXXX")

fetch()
{
	local name=$1 digest=$2 url=$3 archive=$output/$1
	if [ ! -f "$archive" ]; then
		curl -fL --retry 2 --connect-timeout 30 --max-time 600 "$url" -o "$work/$name"
		printf '%s  %s\n' "$digest" "$work/$name" | sha256sum -c -
		mv "$work/$name" "$archive"
	fi
	printf '%s  %s\n' "$digest" "$archive" | sha256sum -c -
	tar -xjf "$archive" -C "$work"
}

fetch busybox-1.36.1.tar.bz2 b8cc24c9574d809e7279c3be349795c5d5ceb6fdf19ca709f80cde50e47de314 \
	https://busybox.net/downloads/busybox-1.36.1.tar.bz2
fetch libtirpc-1.3.4.tar.bz2 1e0b0c7231c5fa122e06c0609a76723664d068b0dba3b8219b63e6340b347860 \
	https://sources.buildroot.net/libtirpc/libtirpc-1.3.4.tar.bz2

(
	cd "$work/libtirpc-1.3.4"
	CC="${prefix}gcc" AR="${prefix}ar" RANLIB="${prefix}ranlib" CFLAGS='-O2 -DGQ' \
		./configure --host="$target" --prefix="$work/tirpc" --disable-gssapi --disable-shared --enable-static
	make -j"$jobs"
	make install
)

source_dir=$work/busybox-1.36.1
for patch_file in "$recipe"/patches/*.patch; do
	patch -d "$source_dir" -p1 --batch --fuzz=0 < "$patch_file"
done
make -C "$source_dir" CROSS_COMPILE="$prefix" defconfig
python3 - "$source_dir/.config" "$recipe/sdk.config" <<'PY'
from pathlib import Path
import sys
config, fragment = map(Path, sys.argv[1:])
def key(line):
    return line.removeprefix('# ').split('=', 1)[0].split(' ', 1)[0]
overrides = fragment.read_text().splitlines()
keys = {key(line) for line in overrides}
base = [line for line in config.read_text().splitlines() if key(line) not in keys]
config.write_text('\n'.join(base + overrides) + '\n')
PY
make -C "$source_dir" CROSS_COMPILE="$prefix" oldconfig < /dev/null
make -C "$source_dir" -j"$jobs" CROSS_COMPILE="$prefix" \
	CONFIG_EXTRA_LDLIBS='tirpc pthread' \
	EXTRA_CFLAGS="-I$work/tirpc/include/tirpc" EXTRA_LDFLAGS="-L$work/tirpc/lib"
elf=$("${prefix}readelf" -hl "$source_dir/busybox")
grep -Eq 'Machine:[[:space:]]+AArch64$' <<< "$elf"
if grep -q INTERP <<< "$elf"; then echo "BusyBox must be static" >&2; exit 1; fi
install -m 0755 "$source_dir/busybox" "$output/busybox.new"
mv "$output/busybox.new" "$output/busybox"
cp "$source_dir/.config" "$output/busybox.config"
sha256sum "$output/busybox"
echo "Built $output/busybox; source and build logs remain in $work"
