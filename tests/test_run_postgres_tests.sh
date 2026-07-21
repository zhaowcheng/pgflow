#!/bin/sh

set -eu
unset PGFLOW_POSTGRES_TESTS_IN_BASH

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

root=$tmpdir/postgres-tests
mkdir -p \
    "$root/lib/copied" \
    "$root/patchelf/bin" \
    "$root/patchelf/share/misc" \
    "$root/src" \
    "$root/tools/bin" \
    "$tmpdir/pghome/bin"
cp "$repo_root/scripts/run_postgres_tests.sh" "$root/run.sh"
chmod +x "$root/run.sh"

cat >"$root/patchelf/bin/file" <<'EOF'
#!/bin/sh
for arg do
    case "$arg" in
        */sample)
            printf '%s: ELF 64-bit executable, dynamically linked\n' "$arg"
            exit 0
            ;;
    esac
done
EOF

cat >"$root/patchelf/bin/patchelf" <<'EOF'
#!/bin/sh
case "$1" in
    --print-interpreter)
        printf '/lib64/ld-pgflow-test.so\n'
        ;;
    --set-interpreter)
        ;;
    *)
        exit 2
        ;;
esac
EOF

chmod +x "$root/patchelf/bin/file" "$root/patchelf/bin/patchelf"
: >"$root/patchelf/share/misc/magic.mgc"
: >"$root/lib/copied/ld-pgflow-test.so"
: >"$root/sample"
chmod +x "$root/sample"
ln -s /bin/bash "$root/tools/bin/bash"

set +e
output=$(cd "$root" && ./run.sh --help 2>&1)
status=$?
set -e
if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
    exit "$status"
fi
printf '%s\n' "$output" | grep -F 'Usage: run.sh PGHOME [make-target] [make-arg ...]' >/dev/null

cat >"$tmpdir/pghome/bin/initdb" <<'EOF'
#!/bin/sh
printf 'LANG=%s\nLC_ALL=%s\n' "${LANG:-}" "${LC_ALL:-}" >"$INITDB_ENV_FILE"
exit 0
EOF

cat >"$tmpdir/pghome/bin/pg_ctl" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$root/tools/bin/id" <<'EOF'
#!/bin/sh
printf 'pgflow\n'
EOF

cat >"$root/tools/bin/make" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$MAKE_ARGS_FILE"
EOF

chmod +x \
    "$tmpdir/pghome/bin/initdb" \
    "$tmpdir/pghome/bin/pg_ctl" \
    "$root/tools/bin/id" \
    "$root/tools/bin/make"
: >"$root/tools/bin/mkdir"
: >"$root/tools/bin/gzip"
: >"$root/tools/bin/lz4"
: >"$root/tools/bin/openssl"
: >"$root/tools/bin/perl"
: >"$root/tools/bin/prove"
: >"$root/tools/bin/tar"
: >"$root/tools/bin/zstd"

MAKE_ARGS_FILE=$tmpdir/make.args
INITDB_ENV_FILE=$tmpdir/initdb.env
export MAKE_ARGS_FILE INITDB_ENV_FILE
(
    cd "$root"
    PGFLOW_TEST_WORKDIR=$tmpdir/work ./run.sh ../pghome installcheck-world >/dev/null
)

assert_make_arg() {
    if ! grep -Fx "$1" "$MAKE_ARGS_FILE" >/dev/null; then
        echo "missing make argument: $1" >&2
        exit 1
    fi
}

assert_make_arg "GZIP_PROGRAM=$root/tools/bin/gzip"
assert_make_arg "LZ4=$root/tools/bin/lz4"
assert_make_arg "MKDIR_P=$root/tools/bin/mkdir -p"
assert_make_arg "OPENSSL=$root/tools/bin/openssl"
assert_make_arg "PERL=$root/tools/bin/perl"
assert_make_arg "PROVE=$root/tools/bin/perl $root/tools/bin/prove"
assert_make_arg "TAR=$root/tools/bin/tar"
assert_make_arg "ZSTD=$root/tools/bin/zstd"

if ! grep -Fx 'LANG=C' "$INITDB_ENV_FILE" >/dev/null; then
    echo "expected LANG=C, got: $(cat "$INITDB_ENV_FILE")" >&2
    exit 1
fi
if ! grep -Fx 'LC_ALL=C' "$INITDB_ENV_FILE" >/dev/null; then
    echo "expected LC_ALL=C, got: $(cat "$INITDB_ENV_FILE")" >&2
    exit 1
fi
