#!/usr/bin/env bash
# Wrap elf executables with LOCALE_ARCHIVE environment.

set -e

progname=$(basename "$0")
if [[ $# != 1 ]]; then
    echo "Usage: $progname ELFDIR" >&2
    exit 1
fi

elfdir=$1

if [ ! -d "$elfdir" ]; then
    echo "error: not a directory: $elfdir" >&2
    exit 1
fi

if [ ! -f "$elfdir/etc/locale-archive" ]; then
    echo "error: missing locale archive: $elfdir/etc/locale-archive" >&2
    exit 1
fi

case "$(uname -m)" in
    x86_64)         ARCH="x86-64" ;;
    aarch64)        ARCH="aarch64" ;;
    loongarch64)    ARCH="LoongArch" ;;
    mips64)         ARCH="MIPS" ;;
    *)              echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

for exe in $(find $elfdir -type f -exec file {} + | grep ELF | grep -E "executable" | grep "$ARCH" | grep "dynamically" | grep -E "SYSV|GNU/Linux" | cut -d: -f1); do
    dir=$(dirname "$exe")
    base=$(basename "$exe")
    hidden="$dir/.$base"

    if [ -e "$hidden" ]; then
        echo "skip: hidden target already exists: $hidden" >&2
        continue
    fi

    mv "$exe" "$hidden"

    rel_dir=${dir#"$elfdir"}
    rel_dir=${rel_dir#/}
    up=
    if [ -n "$rel_dir" ]; then
        old_ifs=$IFS
        IFS=/
        for _part in $rel_dir; do
            up="../${up}"
        done
        IFS=$old_ifs
    fi
    [ -n "$up" ] || up="."

    cat > "$exe" <<EOF
#!/bin/sh
SELFDIR=\$(dirname "\$0")
ELFDIR=\$(CDPATH= cd -- "\$SELFDIR/$up" && pwd)
export LOCALE_ARCHIVE="\$ELFDIR/etc/locale-archive"
exec "\$SELFDIR/.$base" "\$@"
EOF

    chmod 755 "$exe"
    echo "wrapped: $exe"
done
