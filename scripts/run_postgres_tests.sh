#!/bin/sh
# Run PostgreSQL regression tests from the packaged test tree.

set -e

script=$0
case "$script" in
    */*) script_dir=${script%/*} ;;
    *) script_dir=. ;;
esac
script_dir=$(CDPATH= cd -- "$script_dir" && pwd)
root=$script_dir
tools_bin=$root/tools/bin

fix_test_interpreters() {
    patchelf_dir=$root/patchelf
    copied_lib_dir=$root/lib/copied

    if [ ! -x "$patchelf_dir/bin/patchelf" ] || [ ! -x "$patchelf_dir/bin/file" ]; then
        echo "error: test package patchelf tools not found: $patchelf_dir" >&2
        exit 1
    fi
    if [ ! -d "$copied_lib_dir" ]; then
        echo "error: test package copied libraries not found: $copied_lib_dir" >&2
        exit 1
    fi

    sample=$(
        cd "$patchelf_dir" &&
            LD_LIBRARY_PATH=null find "$root" \
                -path "$patchelf_dir" -prune -o \
                -type f -exec ./bin/file -m ./share/misc/magic.mgc {} + |
            awk -F: '/ELF/ && /executable/ && /dynamically/ {print $1; exit}'
    )
    if [ -z "$sample" ]; then
        return 0
    fi

    interp_name=$(basename "$(cd "$patchelf_dir" && LD_LIBRARY_PATH=null ./bin/patchelf --print-interpreter "$sample")")
    interp_path=$copied_lib_dir/$interp_name
    if [ ! -f "$interp_path" ]; then
        echo "error: test package interpreter not found: $interp_path" >&2
        exit 1
    fi

    cd "$patchelf_dir" &&
        LD_LIBRARY_PATH=null find "$root" \
            -path "$patchelf_dir" -prune -o \
            -type f -exec ./bin/file -m ./share/misc/magic.mgc {} + |
        awk -F: '/ELF/ && /executable/ && /dynamically/ {print $1}' |
        while IFS= read -r bin; do
            current=$(cd "$patchelf_dir" && LD_LIBRARY_PATH=null ./bin/patchelf --print-interpreter "$bin")
            if [ "$current" != "$interp_path" ]; then
                cd "$patchelf_dir" && LD_LIBRARY_PATH=null ./bin/patchelf --set-interpreter "$interp_path" "$bin"
            fi
        done
}

fix_test_interpreters

# 修正测试包 ELF interpreter 会刷新 ecpg/preproc/ecpg 的 mtime；
# ECPG installcheck 依赖 mtime 判断是否重建测试程序，这里再次刷新预构建产物，避免目标机调用 gcc。
if [ -d "$root/src/src/interfaces/ecpg/test" ]; then
    find "$root/src/src/interfaces/ecpg/test" -type f -exec touch {} +
    find "$root/src/src/interfaces/ecpg/test" -type f -perm -111 -exec touch {} +
fi

ecpg_schedule=$root/src/src/interfaces/ecpg/test/ecpg_schedule
if [ -f "$ecpg_schedule" ]; then
    ecpg_testdir=$root/src/src/interfaces/ecpg/test
    awk '/^test: / { print $2 }' "$ecpg_schedule" |
    while IFS= read -r ecpg_test; do
        [ -n "$ecpg_test" ] || continue
        : > "$ecpg_testdir/$ecpg_test.c"
        expected_name=$(printf '%s' "$ecpg_test" | tr / -)
        : > "$ecpg_testdir/expected/$expected_name.c"
    done
fi

if [ -z "${PGFLOW_POSTGRES_TESTS_IN_BASH:-}" ]; then
    export PGFLOW_POSTGRES_TESTS_IN_BASH=1
    exec "$tools_bin/bash" "$script" "$@"
fi

set -euo pipefail

usage() {
    cat >&2 <<EOF
Usage: $(basename "$0") PGHOME [make-target] [make-arg ...]

Default target: installcheck-world
EOF
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
esac

if [[ $# -lt 1 ]]; then
    usage
    exit 1
fi
pghome=$(CDPATH= cd -- "$1" && pwd)
shift

target=${1:-installcheck-world}
if [[ $# -gt 0 ]]; then
    shift
fi

if [[ ! -d $pghome/bin ]]; then
    echo "error: PostgreSQL home not found: $pghome" >&2
    exit 1
fi

srcdir=$root/src
workdir=${PGFLOW_TEST_WORKDIR:-${TMPDIR:-/tmp}/pgflow-postgres-tests.$$}
pgdata=$workdir/data
socketdir=$workdir/socket
logfile=$workdir/postgres.log
port=${PGPORT:-65432}

mkdir -p "$workdir" "$socketdir"

export PATH="$tools_bin:$pghome/bin:$PATH"
export PERL5LIB="$root/lib/copied/perl:$srcdir/src/test/perl${PERL5LIB:+:$PERL5LIB}"
export TCLLIBPATH="$pghome/lib/copied/tcl${TCLLIBPATH:+ $TCLLIBPATH}"
export LOCALE_ARCHIVE="$pghome/lib/copied/locale-archive"
export PGHOST="$socketdir"
export PGPORT="$port"
export PGDATABASE=postgres
export PGUSER=${PGUSER:-$("$tools_bin/id" -un)}
export PG_REGRESS="$srcdir/src/test/regress/pg_regress"
export PG_ISOLATION_REGRESS="$srcdir/src/test/isolation/pg_isolation_regress"
export PG_TEST_SHELL="$tools_bin/sh"
export PROVE="$tools_bin/perl $tools_bin/prove"
export PERL="$tools_bin/perl"
export SHELL="$tools_bin/bash"

if [[ ! -d $srcdir ]]; then
    echo "error: PostgreSQL test source tree not found: $srcdir" >&2
    exit 1
fi

if [[ -e $pgdata/PG_VERSION ]]; then
    "$pghome/bin/pg_ctl" -D "$pgdata" -m fast -w stop >/dev/null 2>&1 || true
    rm -rf "$pgdata"
fi

"$pghome/bin/initdb" -D "$pgdata" --no-locale --encoding=UTF8

cleanup() {
    "$pghome/bin/pg_ctl" -D "$pgdata" -m fast -w stop >/dev/null 2>&1 || true
}
trap cleanup EXIT

"$pghome/bin/pg_ctl" -D "$pgdata" \
    -o "-k '$socketdir' -p $port -c listen_addresses='' -c max_connections=200" \
    -l "$logfile" -w start

cd "$srcdir"
make "$target" \
    bindir="$pghome/bin" \
    libdir="$pghome/lib" \
    pkglibdir="$pghome/lib" \
    datadir="$pghome/share" \
    abs_top_builddir="$srcdir" \
    abs_top_srcdir="$srcdir" \
    PG_CONFIG="$pghome/bin/pg_config" \
    "$@"
