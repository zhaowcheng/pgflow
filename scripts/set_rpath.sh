#!/usr/bin/env bash
# Set the rpath of all elf files in `ELFDIR` to relative paths to `LIBDIRS`.

set -e

PROGNAME=$(basename "$0")
if [[ $# != 2 ]]; then
    echo "Usage: $PROGNAME ELFDIR LIBDIRS" >&2
    exit 1
fi

ELFDIR=$1
LIBDIRS=$2

IFS=':' read -r -a libdirs <<< "$LIBDIRS"

case "$(uname -m)" in
    x86_64)         ARCH="x86-64" ;;
    aarch64)        ARCH="aarch64" ;;
    loongarch64)    ARCH="LoongArch" ;;
    mips64)         ARCH="MIPS" ;;
    *)              echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

for elf in $(find "$ELFDIR" -type f -exec file {} + | grep ELF | grep -E "executable|shared object" | grep "$ARCH" | grep "dynamically" | grep -E "SYSV|GNU/Linux" | cut -d: -f1); do
    elf_parentdir=$(dirname "$elf")

    rpaths=()
    for libdir in "${libdirs[@]}"; do
        relative_path=$(realpath --relative-to="$elf_parentdir" "$libdir")
        if [[ $relative_path == '.' ]]; then
            rpaths+=("\$ORIGIN")
        else
            rpaths+=("\$ORIGIN/$relative_path")
        fi
    done

    relative_rpath=$(IFS=:; echo "${rpaths[*]}")

    if [[ $(patchelf --print-rpath "$elf") != "$relative_rpath" ]]; then
        echo "Set the rpath of $elf to $relative_rpath"
        patchelf --set-rpath "$relative_rpath" "$elf" --force-rpath
    fi
done
