#!/usr/bin/env bash
# Copy the build Python standard library into DESTDIR.

set -e

progname=$(basename "$0")
if [[ $# != 1 ]]; then
    echo "Usage: $progname DESTDIR" >&2
    exit 1
fi

destdir=$1

if command -v python >/dev/null 2>&1; then
    pycmd=python
elif command -v python3 >/dev/null 2>&1; then
    pycmd=python3
else
    echo "error: python not found in PATH" >&2
    exit 1
fi

for path in $($pycmd -c "import sys; print('\n'.join(sys.path[1:]))"); do
    if [[ -e $path/abc.py ]]; then
        mkdir -p "$destdir"
        cp -rv "$path"/* "$destdir"/
        find "$destdir" -name "*.pyc" -exec rm -fv {} +
        find "$destdir" -name "*.pyo" -exec rm -fv {} +
        find "$destdir" -name "python.o" -exec rm -fv {} +
        rm -rfv "$destdir"/site-packages/*
        exit 0
    fi
done

echo "error: Python standard library not found in sys.path" >&2
exit 1
