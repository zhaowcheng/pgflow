#!/usr/bin/env bash
# Setup for postgres.

set -e

INSTDIR=$(dirname $(dirname $(realpath $0)))
BINDIR=$INSTDIR/bin
PATCHELFDIR=$(dirname $(realpath $0))/patchelf
cd $PATCHELFDIR
INTERP_NAME=$(basename $(./bin/patchelf --print-interpreter $BINDIR/postgres))
INTERP_PATH=$INSTDIR/lib/copied/$INTERP_NAME

for bin in $(find $BINDIR -type f -exec file {} + | grep ELF | cut -d: -f1); do
    if [[ $(./bin/patchelf --print-interpreter $bin) != $INTERP_PATH ]]; then
        echo "Set the interpreter of $bin to $INTERP_PATH"
        ./bin/patchelf --set-interpreter $INTERP_PATH $bin
    fi  
done