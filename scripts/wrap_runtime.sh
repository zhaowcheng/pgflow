#!/usr/bin/env bash
# Wrap elf executables with runtime environment variables.

set -e

progname=$(basename "$0")
if [[ $# -lt 2 || $# -gt 4 ]]; then
    echo "Usage: $progname ELFDIR LOCALE_ARCHIVE_SAVEDIR [PYTHONDIR] [PERLDIR]" >&2
    exit 1
fi

elfdir=$1
locale_archive_savedir=$2
pythondir=${3:-}
perldir=${4:-}

if [ ! -d "$elfdir" ]; then
    echo "error: not a directory: $elfdir" >&2
    exit 1
fi

if [[ $locale_archive_savedir = /* ]]; then
    echo "error: LOCALE_ARCHIVE_SAVEDIR must be relative to ELFDIR: $locale_archive_savedir" >&2
    exit 1
fi

if [ ! -f "$elfdir/$locale_archive_savedir/locale-archive" ]; then
    echo "error: missing locale archive: $elfdir/$locale_archive_savedir/locale-archive" >&2
    exit 1
fi

if [[ -n $pythondir && ! -d $pythondir ]]; then
    echo "error: not a directory: $pythondir" >&2
    exit 1
fi

if [[ -n $perldir && ! -d $perldir ]]; then
    echo "error: not a directory: $perldir" >&2
    exit 1
fi

case "$(uname -m)" in
    x86_64)         ARCH="x86-64" ;;
    aarch64)        ARCH="aarch64" ;;
    loongarch64)    ARCH="LoongArch" ;;
    mips64)         ARCH="MIPS" ;;
    *)              echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

python_env() {
    local rel_python=$1

    cat <<EOF
PYTHONDIR=\$(CDPATH= cd -- "\$ELFDIR/$rel_python" && pwd)
export PYTHONHOME="\$PYTHONDIR"
export PYTHONPATH="\$PYTHONDIR:\$PYTHONDIR/lib-dynload\${PYTHONPATH:+:\$PYTHONPATH}"
EOF
}

perl_env() {
    local rel_perl=$1

    cat <<EOF
PERLDIR=\$(CDPATH= cd -- "\$ELFDIR/$rel_perl" && pwd)
export PERL5LIB="\$PERLDIR\${PERL5LIB:+:\$PERL5LIB}"
EOF
}

inject_python_env() {
    local exe=$1
    local rel_python=$2
    local tmp

    if grep -q 'PYTHONDIR=' "$exe"; then
        echo "skip: Python environment already exists: $exe" >&2
        return 0
    fi

    tmp=$(mktemp)
    awk -v rel_python="$rel_python" '
        {
            print
            if ($0 ~ /^export LOCALE_ARCHIVE=/) {
                print "PYTHONDIR=$(CDPATH= cd -- \"$ELFDIR/" rel_python "\" && pwd)"
                print "export PYTHONHOME=\"$PYTHONDIR\""
                print "export PYTHONPATH=\"$PYTHONDIR:$PYTHONDIR/lib-dynload${PYTHONPATH:+:$PYTHONPATH}\""
            }
        }
    ' "$exe" > "$tmp"
    cat "$tmp" > "$exe"
    rm -f "$tmp"
    chmod 755 "$exe"
    echo "wrapped Python: $exe"
}

rel_python=
if [[ -n $pythondir ]]; then
    rel_python=$(realpath --relative-to="$elfdir" "$pythondir")
fi

rel_perl=
if [[ -n $perldir ]]; then
    rel_perl=$(realpath --relative-to="$elfdir" "$perldir")
fi

for exe in $(find "$elfdir" -type f -not -name ".*" -exec file {} + | grep ELF | grep -E "executable" | grep "$ARCH" | grep "dynamically" | grep -E "SYSV|GNU/Linux" | cut -d: -f1); do
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
export LOCALE_ARCHIVE="\$ELFDIR/$locale_archive_savedir/locale-archive"
$(if [[ -n $rel_perl ]]; then perl_env "$rel_perl"; fi)
$(if [[ -n $rel_python ]]; then python_env "$rel_python"; fi)
exec "\$SELFDIR/.$base" "\$@"
EOF

    chmod 755 "$exe"
    echo "wrapped: $exe"
done

if [[ -n $rel_python ]]; then
    for exe in $(find "$elfdir" -type f -not -name ".*"); do
        dir=$(dirname "$exe")
        base=$(basename "$exe")
        hidden="$dir/.$base"

        if [[ ! -f $hidden ]]; then
            continue
        fi
        if ! head -n 1 "$exe" | grep -q '^#!/bin/sh$'; then
            continue
        fi
        inject_python_env "$exe" "$rel_python"
    done
fi
