#!/usr/bin/env bash
# Wrap selected executables with runtime environment variables.

set -e

progname=${0##*/}
if [[ $# != 3 ]]; then
    echo "Usage: $progname TOPDIR BINS ENVS" >&2
    exit 1
fi

topdir=$1
bins_arg=$2
envs_arg=$3

if [[ ! -d $topdir ]]; then
    echo "error: not a directory: $topdir" >&2
    exit 1
fi

topdir=$(CDPATH= cd -- "$topdir" && pwd)

split_colon() {
    local input=$1
    local token=
    local ch=
    local escaped=0
    SPLIT_COLON_RESULT=()

    for ((i = 0; i < ${#input}; i++)); do
        ch=${input:i:1}
        if ((escaped)); then
            token+=$ch
            escaped=0
        elif [[ $ch == '\' ]]; then
            escaped=1
        elif [[ $ch == ':' ]]; then
            SPLIT_COLON_RESULT+=("$token")
            token=
        else
            token+=$ch
        fi
    done

    if ((escaped)); then
        token+='\\'
    fi
    SPLIT_COLON_RESULT+=("$token")
}

split_colon "$bins_arg"
bins=("${SPLIT_COLON_RESULT[@]}")
split_colon "$envs_arg"
envs=("${SPLIT_COLON_RESULT[@]}")

validate_env_name() {
    [[ $1 =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

write_env_exports() {
    local envspec=
    local name=
    local value=

    for envspec in "${envs[@]}"; do
        [[ -n $envspec ]] || continue
        if [[ $envspec != *=* ]]; then
            echo "error: invalid env spec: $envspec" >&2
            exit 1
        fi
        name=${envspec%%=*}
        value=${envspec#*=}
        if ! validate_env_name "$name"; then
            echo "error: invalid env name: $name" >&2
            exit 1
        fi
        printf 'export %s="%s"\n' "$name" "$value"
    done
}

for relbin in "${bins[@]}"; do
    [[ -n $relbin ]] || continue
    if [[ $relbin = /* || $relbin = *..* ]]; then
        echo "error: BINS entry must be relative to TOPDIR: $relbin" >&2
        exit 1
    fi

    exe=$topdir/$relbin
    if [[ ! -f $exe ]]; then
        echo "error: executable not found: $exe" >&2
        exit 1
    fi

    dir=${exe%/*}
    base=${exe##*/}
    hidden=$dir/.$base

    if [[ -e $hidden ]]; then
        echo "skip: hidden target already exists: $hidden" >&2
        continue
    fi

    rel_dir=${relbin%/*}
    if [[ $rel_dir == "$relbin" ]]; then
        rel_dir=
    fi
    up=
    if [[ -n $rel_dir ]]; then
        old_ifs=$IFS
        IFS=/
        for _part in $rel_dir; do
            up="../${up}"
        done
        IFS=$old_ifs
    fi
    [[ -n $up ]] || up=.

    mv "$exe" "$hidden"

    {
        cat <<EOF
#!/bin/sh
case "\$0" in
    */*) SELFDIR=\${0%/*} ;;
    *) SELFDIR=. ;;
esac
TOPDIR=\$(CDPATH= cd -- "\$SELFDIR/$up" && pwd)
EOF
        write_env_exports
        cat <<EOF
exec "\$SELFDIR/.$base" "\$@"
EOF
    } > "$exe"

    chmod 755 "$exe"
    echo "wrapped: $exe"
done
