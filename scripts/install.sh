#!/usr/bin/env bash
# pgflow package install script.  The archive layout is:
# .
# |-- content/
# |-- install.sh
# |-- patchelf/

set -e

die() {
    echo "$*" >&2
    exit 1
}

common_topdir() {
    dirname "$(realpath "${BASH_SOURCE[0]}")"
}

patchelf_dir() {
    echo "$(common_topdir)/patchelf"
}

file_find() {
    local patchelfdir=$1

    shift
    (cd "$patchelfdir" && LD_LIBRARY_PATH=null find "$@" -type f -exec ./bin/file -m ./share/misc/magic.mgc {} +)
}

copy_content() {
    local instdir=$1
    local cntdir

    if [[ $# -lt 1 ]]; then
        die "copy_content requires INSTDIR"
    fi

    cntdir=$(common_topdir)/content
    mkdir -p "$instdir"
    cp -av "$cntdir"/. "$instdir"
    chmod -R +w "$instdir"/*
}

detect_arch() {
    case "$(uname -m)" in
        x86_64)         echo "x86-64" ;;
        aarch64)        echo "aarch64" ;;
        loongarch64)    echo "LoongArch" ;;
        *)              die "Unsupported architecture: $(uname -m)" ;;
    esac
}

first_elf_executable() {
    local paths=()
    local path

    for path in "$@"; do
        if [[ -e $path ]]; then
            paths+=("$path")
        fi
    done
    if [[ ${#paths[@]} == 0 ]]; then
        return 0
    fi

    file_find "$(patchelf_dir)" "${paths[@]}" \
        | awk -F: '/ELF/ && /executable/ && first == "" {first = $1} END {if (first != "") print first}'
}

has_elf_executable() {
    local instdir=$1
    local find_args=()
    local excludedir

    shift
    while [[ $# -gt 0 ]]; do
        excludedir=${1#/}
        excludedir=${excludedir%/}
        if [[ -n $excludedir ]]; then
            find_args+=(-not -path "$instdir/$excludedir" -not -path "$instdir/$excludedir/*")
        fi
        shift
    done

    file_find "$(patchelf_dir)" "$instdir" "${find_args[@]}" \
        | awk '/ELF/ && /executable/ {found = 1} END {exit !found}'
}

elf_executable_paths() {
    local arch=$1

    grep ELF \
        | grep -E "executable" \
        | grep "$arch" \
        | grep "dynamically" \
        | grep -E "SYSV|GNU/Linux" \
        | cut -d: -f1
}

interpreter_path_from_probe() {
    local patchelf_dir=$1
    local exec_path=$2
    local copied_lib_dir=$3
    local interp_name

    interp_name=$(basename "$(cd "$patchelf_dir" && LD_LIBRARY_PATH=null ./bin/patchelf --print-interpreter "$exec_path")")
    echo "$copied_lib_dir/$interp_name"
}

set_interpreter_for_paths() {
    local patchelf_dir=$1
    local interp_path=$2
    local bin

    while IFS= read -r bin; do
        if [[ $(cd "$patchelf_dir" && LD_LIBRARY_PATH=null ./bin/patchelf --print-interpreter "$bin") != "$interp_path" ]]; then
            echo "Set the interpreter of $bin to $interp_path"
            (cd "$patchelf_dir" && LD_LIBRARY_PATH=null ./bin/patchelf --set-interpreter "$interp_path" "$bin")
        fi
    done
}

set_interpreter() {
    if [[ $# -lt 1 ]]; then
        die "set_interpreter requires INSTDIR"
    fi

    local instdir=$1
    local bindir=$instdir/bin
    local libdir=$instdir/lib
    local patchelf_dir
    local copied_lib_dir
    local find_args=()
    local excludedir
    local exec_path
    local interp_path
    local arch

    shift
    while [[ $# -gt 0 ]]; do
        excludedir=${1#/}
        excludedir=${excludedir%/}
        if [[ -n $excludedir ]]; then
            find_args+=(-not -path "$instdir/$excludedir" -not -path "$instdir/$excludedir/*")
        fi
        shift
    done

    patchelf_dir=$(patchelf_dir)
    if [[ -d $instdir/lib/copied ]]; then
        copied_lib_dir=$instdir/lib/copied
    elif [[ -d $instdir/../lib/copied ]]; then
        copied_lib_dir=$instdir/../lib/copied
    else
        copied_lib_dir=$instdir/lib/copied
    fi

    exec_path=$(first_elf_executable "$bindir" "$libdir")
    if [[ -z $exec_path ]]; then
        exec_path=$(first_elf_executable "$instdir")
    fi
    if [[ -z $exec_path ]]; then
        return 0
    fi

    interp_path=$(interpreter_path_from_probe "$patchelf_dir" "$exec_path" "$copied_lib_dir")
    arch=$(detect_arch)

    file_find "$patchelf_dir" "$instdir" "${find_args[@]}" \
        | elf_executable_paths "$arch" \
        | set_interpreter_for_paths "$patchelf_dir" "$interp_path"
}

fix_python_scripts() {
    local instdir=$1
    local bindir=$instdir/bin
    local pyprog
    local py

    pyprog=$(ls "$bindir" | grep -E '^python[0-9]+\.[0-9]+$' | head -n 1)
    if [[ -z $pyprog ]]; then
        pyprog=python
    fi

    for py in $(file_find "$(patchelf_dir)" "$bindir" | grep "Python script" | cut -d: -f1); do
        sed -i "1i #\!$bindir/$pyprog" "$py"
        sed -i "2d" "$py"
    done
}

progname=$(basename "$0")
if [[ $# != 1 ]]; then
    echo "Usage: $progname INSTDIR" >&2
    exit 1
fi

instdir=$1
mkdir -p $instdir
instdir=$(realpath "$instdir")

copy_content "$instdir"

excludedirs=()
if [[ -f $instdir/bin/postgres ]]; then
    excludedirs+=("tools" "drivers")
fi
if [[ -d $instdir/jdk ]]; then
    excludedirs+=("jdk")
fi

if [[ -d $instdir/unixodbc ]]; then
    set_interpreter "$instdir/unixodbc"
elif has_elf_executable "$instdir" "${excludedirs[@]}"; then
    set_interpreter "$instdir" "${excludedirs[@]}"
fi

if [[ -d $instdir/jdk ]] && has_elf_executable "$instdir/jdk"; then
    set_interpreter "$instdir/jdk"
fi

if [[ -f $instdir/bin/python ]]; then
    fix_python_scripts "$instdir"
fi
