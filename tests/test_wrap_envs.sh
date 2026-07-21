#!/bin/sh
set -eu
repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
fail() { echo "error: $*" >&2; exit 1; }
make_programs() {
    mkdir -p "$1"
    cat >"$1/alpha" <<'EOF'
#!/bin/sh
printf 'NAME=%s\nENV=%s\nARG=%s\n' "${0##*/}" "${WRAP_TEST_ENV:-}" "${1:-}"
exit "${2:-0}"
EOF
    cp "$1/alpha" "$1/beta"
    chmod +x "$1/alpha" "$1/beta"
    ln -s alpha "$1/alias"
}

root="$tmpdir/package root"
make_programs "$root/bin"
"$repo_root/scripts/wrap_envs.sh" "$root" bin 'WRAP_TEST_ENV=$TOPDIR/runtime'
for name in alpha beta alias; do
    [ -f "$root/bin/$name" ] || fail "missing wrapper: $name"
    [ -e "$root/.bin/$name" ] || fail "missing original: $name"
done
output=$("$root/bin/alpha" hello)
printf '%s\n' "$output" | grep -Fx 'NAME=alpha' >/dev/null
printf '%s\n' "$output" | grep -Fx "ENV=$root/runtime" >/dev/null
printf '%s\n' "$output" | grep -Fx 'ARG=hello' >/dev/null
set +e
"$root/bin/alpha" ignored 7 >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 7 ] || fail "expected exit 7, got $status"

nested="$tmpdir/tests"
make_programs "$nested/tools/bin"
"$repo_root/scripts/wrap_envs.sh" "$nested" tools/bin 'WRAP_TEST_ENV=$TOPDIR/lib'
output=$("$nested/tools/bin/alpha")
printf '%s\n' "$output" | grep -Fx "ENV=$nested/lib" >/dev/null

escaped="$tmpdir/escaped"
make_programs "$escaped/bin"
"$repo_root/scripts/wrap_envs.sh" "$escaped" bin 'WRAP_TEST_ENV=left\:right'
output=$("$escaped/bin/alpha")
printf '%s\n' "$output" | grep -Fx 'ENV=left:right' >/dev/null

for case_name in conflict invalid child unsafe; do
    make_programs "$tmpdir/$case_name/bin"
done
mkdir "$tmpdir/conflict/.bin"
if "$repo_root/scripts/wrap_envs.sh" "$tmpdir/conflict" bin A=b >/dev/null 2>&1; then
    fail 'expected conflict failure'
fi
if "$repo_root/scripts/wrap_envs.sh" "$tmpdir/invalid" bin 1BAD=x >/dev/null 2>&1; then
    fail 'expected invalid env failure'
fi
mkdir "$tmpdir/child/bin/subdir"
if "$repo_root/scripts/wrap_envs.sh" "$tmpdir/child" bin A=b >/dev/null 2>&1; then
    fail 'expected child directory failure'
fi
if "$repo_root/scripts/wrap_envs.sh" "$tmpdir/unsafe" ../bin A=b >/dev/null 2>&1; then
    fail 'expected unsafe path failure'
fi
for case_name in conflict invalid child unsafe; do
    [ -f "$tmpdir/$case_name/bin/alpha" ] || fail "preflight moved $case_name"
done
