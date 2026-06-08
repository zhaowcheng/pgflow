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

tclparent=$(dirname "$tcllib")
if [[ -d $tclparent/tcl8 ]]; then
    cp -rv "$tclparent/tcl8" "$(dirname "$destdir")"/
fi

while IFS= read -r path; do
    if [[ ! -d $path ]]; then
        continue
    fi
    if [[ -d $path/tcl8 ]]; then
        cp -rv "$path/tcl8" "$destdir"/
    fi
    while IFS= read -r pkgdir; do
        cp -rv "$pkgdir" "$destdir"/
    done < <(find "$path" -mindepth 1 -maxdepth 1 -type d -name "*[0-9]*" -exec test -f "{}/pkgIndex.tcl" \; -print)
done < <(printf 'puts [join $auto_path "\n"]\n' | "$tclsh")
