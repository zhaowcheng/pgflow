#!/bin/bash -e
# Set the interpreter of all elf files in `ELFDIR` to `INTERP`.

PROGNAME=$(basename $0)
if [[ $# != 2 ]]; then
    echo "Usage: $PROGNAME ELFDIR INTERP" >&2
    exit 1
fi

ELFDIR=$1
INTERP=$2

for elf in $(find $ELFDIR -type f -exec file {} + | grep ELF | cut -d: -f1); do
    if [[ $(patchelf --print-interpreter $elf) != $INTERP ]]; then
        echo "Set the interpreter of $elf to $INTERP"
        patchelf --set-interpreter $INTERP $elf
    fi  
done
