#!/bin/bash -e
# Set the rpath of all elf files in `ELFDIR` to relative paths to `LIBDIR`.

PROGNAME=$(basename $0)
if [[ $# != 2 ]]; then
    echo "Usage: $PROGNAME ELFDIR LIBDIR" >&2
    exit 1
fi

ELFDIR=$1
LIBDIR=$2

for elf in $(find $ELFDIR -type f -exec file {} + | grep ELF | cut -d: -f1); do
    elf_parentdir=$(dirname $elf)
    relative_path=$(realpath --relative-to=$elf_parentdir $LIBDIR)
    if [[ $relative_path == '.' ]]; then
        relative_rpath="\$ORIGIN"
    else
        relative_rpath="\$ORIGIN/$relative_path"
    fi
    if [[ $(patchelf --print-rpath $elf) != $relative_rpath ]]; then
        echo "Set the rpath of $elf to $relative_rpath"
        patchelf --set-rpath $relative_rpath $elf
    fi  
done
