#!/bin/bash -e
# Setup for postgres.

INSTDIR=$(dirname $(dirname $(realpath $0)))
BINDIR=$INSTDIR/bin
export PATH=$INSTDIR/scripts:$PATH
INTERP_NAME=$(basename $(patchelf --print-interpreter $BINDIR/postgres))
INTERP_PATH=$INSTDIR/lib/$INTERP_NAME

for bin in $(find $BINDIR -type f -exec file {} + | grep ELF | cut -d: -f1); do
    if [[ $(patchelf --print-interpreter $bin) != $INTERP_PATH ]]; then
        echo "Set the interpreter of $bin to $INTERP_PATH"
        patchelf --set-interpreter $INTERP_PATH $bin
    fi  
done
