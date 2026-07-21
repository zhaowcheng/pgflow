# PostgreSQL 测试包相对路径启动修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复测试包在 Rocky Linux 9 中以 `pgflow` 用户通过 `./run.sh` 启动时报找不到脚本的问题，并完成真实 PostgreSQL 回归测试。

**Architecture:** 保持现有测试包布局和两阶段 shell 启动方式不变。先修复 `fix_test_interpreters` 对当前目录的泄漏，再把 PostgreSQL Makefile 中固化的构建机工具显式改写为包内工具，并补齐匹配 glibc 的 `locale`。容器的 PID 1 不回收孤儿进程属于运行环境问题，验收时通过子进程回收器隔离处理。

**Tech Stack:** POSIX shell、GNU find、Docker MCP、PostgreSQL `installcheck-world`

## Global Constraints

- 使用 `192.168.0.200` 上现有的 `rockylinux9` 容器。
- 容器内所有验收命令以 `pgflow` 用户运行。
- 保留工作区已有未提交修改，不创建提交。
- 只修复真实 `installcheck-world` 逐步确认的可移植性问题，不做无关重构。

---

### Task 1: 修复测试启动脚本并完成容器验收

**Files:**
- Create: `tests/test_run_postgres_tests.sh`
- Modify: `scripts/run_postgres_tests.sh:44-55`

**Interfaces:**
- Consumes: 测试包内的 `patchelf/bin/file`、`patchelf/bin/patchelf`、`tools/bin/bash`。
- Produces: 从测试包目录执行 `./run.sh` 时，重新进入 Bash 后仍能找到原脚本，并保持相对 `PGHOME` 的解析基准。

- [x] **Step 1: 写入失败回归测试**

创建一个临时测试包 fixture，放入最小 fake `file`、`patchelf`、loader 和 Bash，然后从 fixture 目录执行 `./run.sh --help`；断言返回成功并输出 usage。

- [x] **Step 2: 确认测试以预期原因失败**

Run: `tests/test_run_postgres_tests.sh`

Expected: FAIL，错误包含 `tools/bin/bash: ./run.sh: No such file or directory`。

- [x] **Step 3: 实施最小修复**

将第二次 ELF 扫描中的目录切换限制在子 shell：

```sh
    (
        cd "$patchelf_dir"
        LD_LIBRARY_PATH=null find "$root" \
            -path "$patchelf_dir" -prune -o \
            -type f -exec ./bin/file -m ./share/misc/magic.mgc {} +
    ) |
        awk -F: '/ELF/ && /executable/ && /dynamically/ {print $1}' |
        while IFS= read -r bin; do
            current=$(cd "$patchelf_dir" && LD_LIBRARY_PATH=null ./bin/patchelf --print-interpreter "$bin")
            if [ "$current" != "$interp_path" ]; then
                cd "$patchelf_dir" && LD_LIBRARY_PATH=null ./bin/patchelf --set-interpreter "$interp_path" "$bin"
            fi
        done
```

- [x] **Step 4: 验证本地回归测试转绿**

Run: `tests/test_run_postgres_tests.sh`

Expected: PASS。

- [x] **Step 5: 在真实容器验证修复脚本**

把修复后的脚本复制到现有测试目录，在 `/home/pgflow/pg18-tests` 以 `pgflow` 用户执行 `./run.sh --help`。

Expected: 返回 0，输出 usage，不再出现相对脚本找不到错误。

- [x] **Step 6: 在真实容器执行完整测试**

定位并解压匹配的 PostgreSQL 产品包，然后以 `pgflow` 用户执行 `./run.sh <PGHOME> installcheck-world`；若出现新的独立失败，返回 systematic-debugging Phase 1 重新取证。

Expected: `installcheck-world` 返回 0，PostgreSQL 正常停止，测试报告无失败。

实际验收还完成了以下修复：

- 通过 make 命令行变量覆盖构建树中的 Nix store 工具路径。
- 将 `LANG`/`LC_ALL` 固定为 `C`，避免继承目标机不可用的 locale。
- 产品包和测试包携带匹配 Nix glibc 的 `locale`，并补齐 gzip、lz4、openssl、zstd 等测试工具。
- 在现有 `tail -f /dev/null` PID 1 的容器中使用临时 child subreaper 完成 recovery 测试；正式重建容器时应使用 Docker `--init`。
