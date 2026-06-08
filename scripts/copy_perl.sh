#!/usr/bin/env bash
# Copy the build Perl library paths into DESTDIR.

set -e

progname=$(basename "$0")
if [[ $# != 1 ]]; then
    echo "Usage: $progname DESTDIR" >&2
    exit 1
fi

destdir=$1

if ! command -v perl >/dev/null 2>&1; then
    echo "error: perl not found in PATH" >&2
    exit 1
fi

copy_config=0
copy_findbin=0

for path in $(perl -e 'print join("\n", @INC, "")'); do
    if [[ -e $path/Config.pm ]]; then
        mkdir -p "$destdir"
        cp -rv "$path"/* "$destdir"/
        copy_config=1
        break
    fi
done

for path in $(perl -e 'print join("\n", @INC, "")'); do
    if [[ -e $path/FindBin.pm ]]; then
        mkdir -p "$destdir"
        cp -rv "$path"/* "$destdir"/
        copy_findbin=1
        break
    fi
done

for path in $(perl -e 'print join("\n", @INC, "")'); do
    if [[ -d $path && $path != "$destdir" ]] && find "$path" -mindepth 1 -maxdepth 1 | grep -q .; then
        mkdir -p "$destdir"
        cp -rv "$path"/* "$destdir"/
    fi
done

find "$destdir" -name "*.pod" -exec rm -fv {} +

if [[ $copy_config != 1 ]]; then
    echo "error: Perl Config.pm path not found in @INC" >&2
    exit 1
fi

if [[ $copy_findbin != 1 ]]; then
    echo "error: Perl FindBin.pm path not found in @INC" >&2
    exit 1
fi
