# 测试内容嵌入程序包实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 PostgreSQL 测试内容放入最终程序包的 `content/tests/`，通过 `include_tests` 控制是否携带，并让 `tests/run.sh` 自动从上一级定位 PGHOME。

**Architecture:** 公共 `pack` 基类负责可选测试内容的统一准备协议，具体流水线仍负责实现 `copy_tests()`。`pack_postgres.stage3()` 在唯一一次归档前调用该协议；测试运行器则依赖固定的 `bin/`、`tests/` 同级布局，不再接收外部 PGHOME 参数。

**Tech Stack:** Python 3.10+、`unittest`、POSIX shell/Bash、xflow.framework

## Global Constraints

- `include_tests` 参数名保持不变；公共默认值保持 `False`，`pack_postgres.Options` 默认值保持 `True`。
- 测试目录固定为 `content/tests/`，与 `content/bin/` 同级。
- 只生成 `postgres-<version>-<system>-glibc<version>.tar.gz`，不再生成 `postgres-tests-*.tar.gz`。
- 测试入口固定为 `tests/run.sh [make-target] [make-arg ...]`，不兼容显式 PGHOME 参数。
- 不改变 PostgreSQL 测试载荷、测试工具集合、ECPG mtime 修正和依赖闭包逻辑。
- 不重构未使用测试接口的其他流水线。

---

## File Structure

- `pipelines/common/pack.py`：定义所有流水线共享的可选测试准备协议，删除独立测试包命名接口。
- `pipelines/pack_postgres.py`：在单一程序包归档前准备可选测试内容。
- `scripts/run_postgres_tests.sh`：从 `tests/` 的上一级自动定位 PostgreSQL 安装根目录。
- `tests/test_package_tests.py`：验证父类协议和 PostgreSQL 打包时序，不依赖远端节点。
- `tests/test_run_postgres_tests.sh`：验证新测试入口、默认目标和参数透传。

### Task 1: 建立公共的可选测试准备协议

**Files:**
- Create: `tests/test_package_tests.py`
- Modify: `pipelines/common/pack.py:102-137`

**Interfaces:**
- Consumes: `self.options.include_tests: bool`、具体流水线的 `copy_tests() -> None`
- Produces: `pack.prepare_tests() -> None`；当且仅当 `include_tests=True` 时调用一次 `copy_tests()`

- [ ] **Step 1: 写父类协议的失败测试**

创建 `tests/test_package_tests.py`：

```python
import unittest
from types import SimpleNamespace

from pipelines.common.pack import pack


class PackHarness(pack):
    def copy_tests(self) -> None:
        self.events.append('copy_tests')


def make_pack(include_tests: bool) -> PackHarness:
    pipeline = object.__new__(PackHarness)
    pipeline.options = SimpleNamespace(include_tests=include_tests)
    pipeline.events = []
    return pipeline


class PrepareTestsTest(unittest.TestCase):
    def test_copies_tests_when_enabled(self) -> None:
        pipeline = make_pack(True)

        pipeline.prepare_tests()

        self.assertEqual(pipeline.events, ['copy_tests'])

    def test_skips_tests_when_disabled(self) -> None:
        pipeline = make_pack(False)

        pipeline.prepare_tests()

        self.assertEqual(pipeline.events, [])

if __name__ == '__main__':
    unittest.main()
```

- [ ] **Step 2: 运行测试并确认按预期失败**

Run: `venv/bin/python -m unittest discover -s tests -p 'test_package_tests.py' -v`

Expected: ERROR，指出 `prepare_tests` 不存在。

- [ ] **Step 3: 实现最小公共协议**

在 `pipelines/common/pack.py` 中删除 `tests_pkgname` 属性，在 `copy_tests()` 后增加：

```python
    def prepare_tests(self) -> None:
        """
        根据流水线参数准备随程序包交付的测试内容。
        """
        if self.options.include_tests:
            self.copy_tests()
```

- [ ] **Step 4: 运行测试并确认通过**

Run: `venv/bin/python -m unittest discover -s tests -p 'test_package_tests.py' -v`

Expected: 2 tests PASS。

- [ ] **Step 5: 提交公共协议**

```bash
git add pipelines/common/pack.py tests/test_package_tests.py
git commit -m "统一程序包测试内容准备接口"
```

### Task 2: 让 PostgreSQL 只归档一次完整程序包

**Files:**
- Modify: `tests/test_package_tests.py`
- Modify: `pipelines/pack_postgres.py:96-105`

**Interfaces:**
- Consumes: `pack.prepare_tests() -> None`、`self.packdir`、`self.pkgname`
- Produces: `pack_postgres.stage3() -> None`，固定按 `copy_deps`、`copy_instscript`、`prepare_tests`、`archive` 的顺序执行

- [ ] **Step 1: 写 PostgreSQL 打包时序的失败测试**

在 `tests/test_package_tests.py` 中增加导入和测试工具：

```python
from pipelines.pack_postgres import pack_postgres


class PostgresHarness(pack_postgres):
    @property
    def pkgname(self) -> str:
        return 'postgres.tar.gz'

    def copy_deps(self) -> None:
        self.events.append('copy_deps')

    def copy_instscript(self, destdir: str) -> None:
        self.events.append(('copy_instscript', destdir))

    def copy_tests(self) -> None:
        self.events.append('copy_tests')

    def prepare_tests(self) -> None:
        self.events.append('prepare_tests')
        super().prepare_tests()

    def archive(self, directory: str, pkgname: str | None = None) -> None:
        self.events.append(('archive', directory, pkgname))


def make_postgres(include_tests: bool) -> PostgresHarness:
    pipeline = object.__new__(PostgresHarness)
    pipeline.options = SimpleNamespace(include_tests=include_tests)
    pipeline.packdir = 'package'
    pipeline.testsdir = 'package/content/tests'
    pipeline.events = []
    return pipeline
```

再增加测试类：

```python
class PostgresStage3Test(unittest.TestCase):
    def test_embeds_tests_before_single_archive_when_enabled(self) -> None:
        pipeline = make_postgres(True)

        pipeline.stage3()

        self.assertEqual(
            pipeline.events,
            [
                'copy_deps',
                ('copy_instscript', 'package'),
                'prepare_tests',
                'copy_tests',
                ('archive', 'package', 'postgres.tar.gz'),
            ],
        )

    def test_archives_program_without_tests_when_disabled(self) -> None:
        pipeline = make_postgres(False)

        pipeline.stage3()

        self.assertEqual(
            pipeline.events,
            [
                'copy_deps',
                ('copy_instscript', 'package'),
                'prepare_tests',
                ('archive', 'package', 'postgres.tar.gz'),
            ],
        )
```

- [ ] **Step 2: 运行测试并确认旧打包顺序失败**

Run: `venv/bin/python -m unittest discover -s tests -p 'test_package_tests.py' -v`

Expected: 两个新增测试 FAIL/ERROR；启用测试时旧实现先归档且尝试生成第二个测试归档，禁用测试时没有经过公共准备协议。

- [ ] **Step 3: 实现单归档打包顺序**

把 `pack_postgres.stage3()` 改为：

```python
    def stage3(self) -> None:
        """
        打包。
        """
        self.copy_deps()
        self.copy_instscript(self.packdir)
        self.prepare_tests()
        self.archive(self.packdir, self.pkgname)
```

- [ ] **Step 4: 运行打包协议测试并确认通过**

Run: `venv/bin/python -m unittest discover -s tests -p 'test_package_tests.py' -v`

Expected: 4 tests PASS，事件记录中始终只有一次 `archive`。

- [ ] **Step 5: 提交 PostgreSQL 单归档改动**

```bash
git add pipelines/pack_postgres.py tests/test_package_tests.py
git commit -m "将 postgres 测试内容并入程序包"
```

### Task 3: 让测试入口自动定位 PGHOME

**Files:**
- Modify: `tests/test_run_postgres_tests.sh:10-130`
- Modify: `scripts/run_postgres_tests.sh:89-119`

**Interfaces:**
- Consumes: `tests/run.sh` 的绝对位置和其上一级安装目录
- Produces: `tests/run.sh [make-target] [make-arg ...]`，默认目标为 `installcheck-world`

- [ ] **Step 1: 把 shell 回归场景改成 bin/tests 同级布局**

在 `tests/test_run_postgres_tests.sh` 中把目录准备改为：

```sh
pghome=$tmpdir/pghome
root=$pghome/tests
mkdir -p \
    "$pghome/bin" \
    "$root/lib/copied" \
    "$root/patchelf/bin" \
    "$root/patchelf/share/misc" \
    "$root/src" \
    "$root/tools/bin"
```

帮助文本断言改为：

```sh
printf '%s\n' "$output" | grep -F 'Usage: run.sh [make-target] [make-arg ...]' >/dev/null
```

所有原来的 `$tmpdir/pghome` 路径改用 `$pghome`。把执行与断言部分改为先验证默认目标，再验证目标和额外参数透传：

```sh
MAKE_ARGS_FILE=$tmpdir/make.args
INITDB_ENV_FILE=$tmpdir/initdb.env
export MAKE_ARGS_FILE INITDB_ENV_FILE
(
    cd "$root"
    PGFLOW_TEST_WORKDIR=$tmpdir/work ./run.sh >/dev/null
)

if ! grep -Fx 'installcheck-world' "$MAKE_ARGS_FILE" >/dev/null; then
    echo "missing default make target: installcheck-world" >&2
    exit 1
fi

(
    cd "$root"
    PGFLOW_TEST_WORKDIR=$tmpdir/work ./run.sh installcheck EXTRA_FLAG=value >/dev/null
)

if ! grep -Fx 'installcheck' "$MAKE_ARGS_FILE" >/dev/null; then
    echo "missing explicit make target: installcheck" >&2
    exit 1
fi
if ! grep -Fx 'EXTRA_FLAG=value' "$MAKE_ARGS_FILE" >/dev/null; then
    echo "missing extra make argument: EXTRA_FLAG=value" >&2
    exit 1
fi

(
    cd "$root"
    PGFLOW_TEST_WORKDIR=$tmpdir/work ./run.sh "$pghome" >/dev/null
)

if ! grep -Fx "$pghome" "$MAKE_ARGS_FILE" >/dev/null; then
    echo "old PGHOME argument was not treated as a make target" >&2
    exit 1
fi
```

保留现有工具参数、`LANG=C` 和 `LC_ALL=C` 断言。

- [ ] **Step 2: 运行 shell 测试并确认按预期失败**

Run: `tests/test_run_postgres_tests.sh`

Expected: FAIL；旧脚本无参数时打印旧 usage 并退出，无法自动定位 `$pghome`。

- [ ] **Step 3: 实现 PGHOME 自动定位和新参数接口**

在 `scripts/run_postgres_tests.sh` 的 `root=$script_dir` 后增加：

```sh
pghome=$(CDPATH= cd -- "$root/.." && pwd)
```

把 usage 和参数解析改为：

```sh
usage() {
    cat >&2 <<EOF
Usage: $(basename "$0") [make-target] [make-arg ...]

Default target: installcheck-world
EOF
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
esac

target=${1:-installcheck-world}
if [[ $# -gt 0 ]]; then
    shift
fi

if [[ ! -d $pghome/bin ]]; then
    echo "error: PostgreSQL home not found: $pghome" >&2
    exit 1
fi
```

删除旧的必填参数数量检查、`pghome` 从 `$1` 解析和对应的首次 `shift`。脚本其余环境变量、服务启停和 `make` 参数保持不变。

- [ ] **Step 4: 运行 shell 测试并确认通过**

Run: `tests/test_run_postgres_tests.sh`

Expected: PASS，无输出。

- [ ] **Step 5: 检查 shell 语法**

Run: `sh -n tests/test_run_postgres_tests.sh && sh -n scripts/run_postgres_tests.sh && bash -n scripts/run_postgres_tests.sh`

Expected: exit 0，无输出。

- [ ] **Step 6: 提交测试入口改动**

```bash
git add scripts/run_postgres_tests.sh tests/test_run_postgres_tests.sh
git commit -m "让 postgres 测试自动定位程序目录"
```

### Task 4: 完整本地回归验证

**Files:**
- Verify: `pipelines/common/pack.py`
- Verify: `pipelines/pack_postgres.py`
- Verify: `scripts/run_postgres_tests.sh`
- Verify: `tests/test_package_tests.py`
- Verify: `tests/test_run_postgres_tests.sh`

**Interfaces:**
- Consumes: 前三个任务的最终实现
- Produces: 可复现的本地验证证据和干净的变更检查结果

- [ ] **Step 1: 运行全部新增回归测试**

Run: `venv/bin/python -m unittest discover -s tests -p 'test_*.py' -v && tests/test_run_postgres_tests.sh`

Expected: 5 个 Python tests 全部 PASS；shell 测试 exit 0。

- [ ] **Step 2: 运行 Python 语法检查**

Run: `venv/bin/python -m compileall -q pipelines tests/test_package_tests.py`

Expected: exit 0，无语法错误。

- [ ] **Step 3: 验证 xflow 能导入流水线**

Run: `venv/bin/xflow -p . --help`

Expected: exit 0，并列出 `init` 和 `run` 命令。

- [ ] **Step 4: 确认独立测试包接口已完全移除**

Run: `if rg -n 'tests_pkgname|postgres-tests-' pipelines scripts tests; then exit 1; fi`

Expected: exit 0，无匹配。

- [ ] **Step 5: 检查变更质量与范围**

Run: `git diff --check HEAD~3..HEAD && git status --short`

Expected: `git diff --check` exit 0；状态中只允许出现本实施计划文件，或者在计划也已提交时完全为空。

- [ ] **Step 6: 记录远端构建验证边界**

本计划不自动触发耗时的远端 PostgreSQL 完整构建。交付时明确说明本地协议测试、脚本测试、导入和语法检查的结果，并注明实际单归档构建及目标机 `installcheck-world` 是否未执行。
