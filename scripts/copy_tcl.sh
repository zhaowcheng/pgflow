#!/usr/bin/env bash
# Copy the build Tcl library path into DESTDIR.

set -e

progname=$(basename "$0")
if [[ $# != 1 ]]; then
    echo "Usage: $progname DESTDIR" >&2
    exit 1
fi

destdir=$1

tclsh=
for name in tclsh tclsh8.7 tclsh8.6; do
    if command -v "$name" >/dev/null 2>&1; then
        tclsh=$(command -v "$name")
        break
    fi
done

if [[ -z $tclsh ]]; then
    echo "error: tclsh not found in PATH" >&2
    exit 1
fi

tcllib=$(printf 'puts [info library]\n' | "$tclsh")
if [[ -z $tcllib || ! -e $tcllib/init.tcl ]]; then
    echo "error: Tcl init.tcl path not found: $tcllib" >&2
    exit 1
fi

mkdir -p "$destdir"
cp -rv "$tcllib"/* "$destdir"/
