# wrap_envs 目录级包装实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 整体隐藏 bin 目录并包装其中全部程序，消除错误信息中带点号的程序名。

**Architecture:** `scripts/wrap_envs.sh` 完成预检、`bin -> .bin` 和 wrapper 生成；Python 层转发 `topdir`、`bindir`、`envs`。正式包和测试包分别包装 `bin`、`tools/bin`。

**Tech Stack:** Bash、Python 3.10+、stdlib `unittest`、xflow

## Global Constraints

- 接口为 `wrap_envs(node, topdir, bindir, envs)`，不再接受程序列表。
- `topdir` 是 wrapper 中 `$TOPDIR` 的根；`bindir` 是安全相对路径。
- 包装全部非目录项；所有可预检错误必须在移动源目录前失败。
- 不修改无关逻辑，不执行远端实际构建。

---

### Task 1: 目录级 shell 包装

**Files:**
- Create: `tests/test_wrap_envs.sh`
- Modify: `scripts/wrap_envs.sh:1-137`

**Interfaces:**
- Consumes: `scripts/wrap_envs.sh TOPDIR BINDIR ENVS`
- Produces: 隐藏原目录，并在原路径生成全部同名 wrapper

- [ ] **Step 1: 编写失败的端到端测试**

创建 `tests/test_wrap_envs.sh`：

```sh
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
```

- [ ] **Step 2: 运行测试确认旧实现失败**

Run: `sh tests/test_wrap_envs.sh`

Expected: FAIL，旧脚本报告 `executable not found`。

- [ ] **Step 3: 替换 shell 实现**

将 `scripts/wrap_envs.sh` 替换为：

```bash
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
        elif [[ $ch == '\' ]]; then escaped=1
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
```

- [ ] **Step 4: 运行 `sh tests/test_wrap_envs.sh`**

Expected: 状态 0。

- [ ] **Step 5: 提交**

```bash
git add tests/test_wrap_envs.sh scripts/wrap_envs.sh
git commit -m "改为按目录包装全部程序"
```

### Task 2: Python 接口与调用方

**Files:**
- Create: `tests/test_wrap_envs_api.py`
- Modify: `pipelines/common/scripts.py:95-113`
- Modify: `pipelines/pack_postgres.py:145-148,197-234`

**Interfaces:**
- Consumes: Task 1 的 `TOPDIR BINDIR ENVS` shell 接口
- Produces: `wrap_envs(node, topdir, bindir, envs) -> CommandResult`

- [ ] **Step 1: 编写失败的参数转发测试**

创建 `tests/test_wrap_envs_api.py`：

```python
import shlex
import unittest
from pipelines.common.scripts import wrap_envs


class FakeNode:
    def __init__(self) -> None:
        self.script = ""
        self.argstr = ""

    def exec_script(self, script: str, argstr: str):
        self.script = script
        self.argstr = argstr
        return "result"


class WrapEnvsTests(unittest.TestCase):
    def test_forwards_bindir_and_all_envs(self) -> None:
        node = FakeNode()
        result = wrap_envs(
            node, "/package root", "tools/bin",
            ("A=one:two", "B=$TOPDIR/lib"),
        )
        self.assertEqual(result, "result")
        self.assertEqual(node.script, "scripts/wrap_envs.sh")
        self.assertEqual(
            shlex.split(node.argstr),
            ["/package root", "tools/bin", r"A=one\:two:B=$TOPDIR/lib"],
        )


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: 运行测试确认旧接口失败**

Run: `venv/bin/python -m unittest tests/test_wrap_envs_api.py -v`

Expected: FAIL，旧接口将字符串 `tools/bin` 当作程序序列处理。

- [ ] **Step 3: 修改 `wrap_envs`**

```python
def wrap_envs(
    node: Node,
    topdir: str | PurePosixPath,
    bindir: str | PurePosixPath,
    envs: list[str] | tuple[str, ...]
) -> CommandResult:
    """
    隐藏 topdir 下的 bin 目录，并为其中全部程序创建环境变量 wrapper。

    :param node: 执行节点。
    :param topdir: wrapper 中 TOPDIR 对应的目标根目录。
    :param bindir: 需要整体 wrap 的 bin 目录，相对 topdir。
    :param envs: 写入 wrapper 的环境变量，格式为 NAME=VALUE。
    :return: 脚本输出。
    """
    argstr = ' '.join(quote(item)
                      for item in (str(topdir), str(bindir), _join_colon(envs)))
    return node.exec_script('scripts/wrap_envs.sh', argstr=argstr)
```

- [ ] **Step 4: 更新调用并删除白名单**

测试包调用：

```python
        wrap_envs(self.node, self.testsdir, 'tools/bin', test_envs)
```

正式包调用：

```python
        wrap_envs(self.node, elfdir, 'bin', envs)
```

完整删除 `runtime_env_bins` 和 `test_env_bins` 两个属性。

- [ ] **Step 5: 运行接口测试和语法检查**

Run: `venv/bin/python -m unittest tests/test_wrap_envs_api.py -v`

Expected: `Ran 1 test ... OK`。

Run: `venv/bin/python -m compileall pipelines`

Expected: 状态 0，无 `SyntaxError`。

- [ ] **Step 6: 提交**

```bash
git add tests/test_wrap_envs_api.py pipelines/common/scripts.py pipelines/pack_postgres.py
git commit -m "更新 wrap_envs 目录参数接口"
```

### Task 3: 完整回归验证

**Files:**
- Test: `tests/test_wrap_envs.sh`
- Test: `tests/test_wrap_envs_api.py`
- Test: `tests/test_run_postgres_tests.sh`

**Interfaces:**
- Consumes: Task 1、Task 2 最终实现
- Produces: 本地验证证据

- [ ] **Step 1: shell 语法检查**

Run: `bash -n scripts/wrap_envs.sh tests/test_wrap_envs.sh`

Expected: 状态 0，无输出。

- [ ] **Step 2: 新旧 shell 回归**

Run: `sh tests/test_wrap_envs.sh && sh tests/test_run_postgres_tests.sh`

Expected: 两个测试均为状态 0。

- [ ] **Step 3: Python 与流水线语法回归**

Run: `venv/bin/python -m unittest tests/test_wrap_envs_api.py -v && venv/bin/python -m compileall pipelines`

Expected: unittest 为 `OK`，compileall 无语法错误。

- [ ] **Step 4: xflow 导入验证**

Run: `venv/bin/xflow -p . --help >/tmp/pgflow-wrap-env-xflow-help.txt`

Expected: 状态 0，完整输出只保存在临时文件。

- [ ] **Step 5: 最终差异检查**

Run: `git diff --check && git status --short`

Expected: diff 检查无输出，状态只包含计划内文件或为空。
