#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: tools/armv7_musl_sysroot_smoke_test.sh [options]

Assemble Zig's ARMv7 musl include layers and verify the headers used by the
Rusty V8 bindgen and C++ builds.

Options:
  --output-dir <dir>  Sysroot directory to create. Defaults to /var/tmp.
  --clang <path>      Clang executable to use. Defaults to clang++.
  -h, --help          Show this help.
USAGE
}

output_dir=""
clang="clang++"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      output_dir="${2:-}"
      shift 2
      ;;
    --clang)
      clang="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

command -v zig >/dev/null 2>&1 || {
  echo "ERROR: zig is required." >&2
  exit 1
}
command -v "$clang" >/dev/null 2>&1 || {
  echo "ERROR: clang executable not found: $clang" >&2
  exit 1
}

if [[ -z "$output_dir" ]]; then
  output_dir="$(mktemp -d /var/tmp/rusty-v8-armv7-musl-sysroot.XXXXXX)"
else
  if [[ -e "$output_dir" ]]; then
    echo "ERROR: output directory already exists: $output_dir" >&2
    exit 1
  fi
  mkdir -p "$output_dir"
fi

zig_lib_dir="$(zig env | python3 -c 'import json, sys; print(json.load(sys.stdin)["lib_dir"])')"
zig_libc_dir="${zig_lib_dir}/libc"
musl_include="${zig_libc_dir}/musl/include"
arm_include="${zig_libc_dir}/include/arm-linux-musl"
linux_include="${zig_libc_dir}/include/arm-linux-any"
generic_linux_include="${zig_libc_dir}/include/any-linux-any"
generic_musl_include="${zig_libc_dir}/include/generic-musl"

for include_dir in \
  "$musl_include" \
  "$arm_include" \
  "$linux_include" \
  "$generic_linux_include" \
  "$generic_musl_include"; do
  test -d "$include_dir"
done

include_dir="${output_dir}/usr/include"
mkdir -p "$include_dir"
# Generic headers must be present first; target-specific headers then override
# them where both layers provide a file.
cp -a "${generic_musl_include}/." "$include_dir/"
cp -a "${generic_linux_include}/." "$include_dir/"
cp -a "${arm_include}/." "$include_dir/"
cp -a "${musl_include}/." "$include_dir/"
# Zig keeps the hard-float ARM ABI header under its explicit name, while Linux's
# generic unistd.h includes the conventional name.
ln -s "unistd-eabi.h" "${include_dir}/asm/unistd.h"

fixture="${output_dir}/header-smoke-test.cc"
cat > "$fixture" <<'EOF'
#include <features.h>
#include <stdint.h>
#include <bits/wordsize.h>
#include <asm/bitsperlong.h>
#include <linux/futex.h>
#include <linux/unistd.h>
#include <asm/unistd.h>

int main() { return 0; }
EOF

"$clang" \
  --target=arm-linux-gnueabihf \
  --sysroot="$output_dir" \
  -nostdinc \
  -isystem "$include_dir" \
  -fsyntax-only \
  "$fixture"

echo "ARMv7 musl sysroot smoke test passed: $output_dir"
