#!/usr/bin/env bash
# Set the interpreter of all elf files in `BINDIR` to `INTERP`.

set -e

PROGNAME=$(basename $0)
if [[ $# != 2 ]]; then
    echo "Usage: $PROGNAME BINDIR INTERP" >&2
    exit 1
fi

BINDIR=$1
INTERP=$2

case "$(uname -m)" in
    x86_64)         ARCH="x86-64" ;;
    aarch64)        ARCH="aarch64" ;;
    loongarch64)    ARCH="LoongArch" ;;
    mips64)         ARCH="MIPS" ;;
    *)              echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

for elf in $(find $BINDIR -type f -exec file {} + | grep ELF | grep -E "executable" | grep "$ARCH" | grep "dynamically" | grep -E "SYSV|GNU/Linux" | cut -d: -f1); do
    if [[ $(patchelf --print-interpreter $elf) != $INTERP ]]; then
        echo "Set the interpreter of $elf to $INTERP"
        patchelf --set-interpreter $INTERP $elf
    fi  
done
