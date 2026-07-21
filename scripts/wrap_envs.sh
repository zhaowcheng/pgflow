#!/usr/bin/env bash
# Wrap all programs in a bin directory with runtime environment variables.
set -e
progname=${0##*/}
if [[ $# != 3 ]]; then
    echo "Usage: $progname TOPDIR BINDIR ENVS" >&2; exit 1
fi
topdir=$1
bindir=$2
envs_arg=$3
if [[ ! -d $topdir ]]; then
    echo "error: not a directory: $topdir" >&2; exit 1
fi
if [[ -z $bindir || $bindir = /* || $bindir = */ || $bindir = *//* || /$bindir/ = */../* || /$bindir/ = */./* ]]; then
    echo "error: BINDIR must be a normalized relative path: $bindir" >&2; exit 1
fi
topdir=$(CDPATH= cd -- "$topdir" && pwd)
source_dir=$topdir/$bindir
parent_dir=${source_dir%/*}
base=${source_dir##*/}
hidden_dir=$parent_dir/.$base
if [[ ! -d $source_dir ]]; then
    echo "error: bin directory not found: $source_dir" >&2; exit 1
fi
if [[ -e $hidden_dir || -L $hidden_dir ]]; then
    echo "error: hidden bin directory already exists: $hidden_dir" >&2; exit 1
fi
split_colon() {
    local input=$1 token= ch= escaped=0
    SPLIT_COLON_RESULT=()
    for ((i = 0; i < ${#input}; i++)); do
        ch=${input:i:1}
        if ((escaped)); then token+=$ch; escaped=0
        elif [[ $ch == '\\' ]]; then escaped=1
        elif [[ $ch == ':' ]]; then SPLIT_COLON_RESULT+=("$token"); token=
        else token+=$ch
        fi
    done
    if ((escaped)); then token+='\\'; fi
    SPLIT_COLON_RESULT+=("$token")
}
split_colon "$envs_arg"
envs=("${SPLIT_COLON_RESULT[@]}")
validate_env_name() { [[ $1 =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; }
for envspec in "${envs[@]}"; do
    [[ -n $envspec ]] || continue
    if [[ $envspec != *=* ]]; then
        echo "error: invalid env spec: $envspec" >&2; exit 1
    fi
    name=${envspec%%=*}
    if ! validate_env_name "$name"; then
        echo "error: invalid env name: $name" >&2; exit 1
    fi
done
write_env_exports() {
    local envspec= name= value=
    for envspec in "${envs[@]}"; do
        [[ -n $envspec ]] || continue
        name=${envspec%%=*}
        value=${envspec#*=}
        printf 'export %s="%s"\n' "$name" "$value"
    done
}
shopt -s nullglob dotglob
entries=("$source_dir"/*)
shopt -u nullglob dotglob
for entry in "${entries[@]}"; do
    if [[ -d $entry ]]; then
        echo "error: child directory is not supported: $entry" >&2; exit 1
    fi
done
up=
old_ifs=$IFS
IFS=/
for _part in $bindir; do up="../${up}"; done
IFS=$old_ifs
mv "$source_dir" "$hidden_dir"
mkdir -m 755 "$source_dir"
for entry in "${entries[@]}"; do
    wrapper=$source_dir/${entry##*/}
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
        cat <<'EOF'
BINDIRNAME=${SELFDIR##*/}
PROGRAM=${0##*/}
exec "$SELFDIR/../.$BINDIRNAME/$PROGRAM" "$@"
EOF
    } >"$wrapper"
    chmod 755 "$wrapper"
    echo "wrapped: $wrapper"
done
