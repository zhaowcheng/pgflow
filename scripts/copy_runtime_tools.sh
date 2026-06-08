#!/usr/bin/env bash
# Copy runtime command-line tools from PATH into DESTDIR/bin.

set -e

progname=$(basename "$0")
if [[ $# -lt 2 ]]; then
    echo "Usage: $progname DESTDIR TOOL [TOOL ...]" >&2
    exit 1
fi

destdir=$1
shift

bindir=$destdir/bin
mkdir -p "$bindir"

for tool in "$@"; do
    toolpath=$(command -v "$tool" || true)
    if [[ -z $toolpath ]]; then
        echo "error: tool not found in PATH: $tool" >&2
        exit 1
    fi

    cp -Lv "$toolpath" "$bindir/$(basename "$tool")"
done
