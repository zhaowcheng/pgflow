#!/bin/bash -e
# Check the deps of all elf files in `ELFDIR`.

PROGNAME=$(basename "$0")
if [[ $# -lt 1 ]]; then
    echo "Usage: $PROGNAME ELFDIR" >&2
    exit 1
fi

ELFDIR=$1

case "$(uname -m)" in
    x86_64)         ARCH="x86-64" ;;
    aarch64)        ARCH="aarch64" ;;
    loongarch64)    ARCH="LoongArch" ;;
    *)              echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

for elf in `find $ELFDIR -type f -exec file {} + | grep "ELF" | grep -E "executable|shared object" | grep "$ARCH" | grep "dynamically" | grep -E "SYSV|GNU/Linux" | cut -d: -f1`; do
    echo "Checking $elf"
    ldd $elf
    if [[ $(ldd $elf 2>&1) == *"not found"* ]]; then
        echo "ERROR: Some dependencies for $elf cannot be found."
        exit 2
    fi
done
