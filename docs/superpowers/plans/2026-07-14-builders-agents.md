# builders AGENTS.md Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `builders/` 生成完整、准确且可验证的子目录维护规范。

**Architecture:** 仅修改 `builders/AGENTS.md`，让它继承根目录通用规则，并集中描述 Docker/Nix 构建环境的目录职责、修改约束、分层验证与安全边界。具体使用步骤继续由 `builders/README.md` 承载，避免重复维护。

**Tech Stack:** Markdown、Dockerfile、Nix flakes、Nix overlays、Nix derivations

## Global Constraints

- 文档适用于 `builders/` 及其全部子目录，并继承仓库根目录 `AGENTS.md`。
- 覆盖 x86_64、aarch64、loongarch64、mips64el 四个平台。
- 不读取或输出 `keys/nix-serve/private.key` 的内容。
- 不把全架构 Docker 构建规定为所有改动的默认验证。
- 未经用户要求，不创建 Git commit。

---

### Task 1: 生成并验证子目录维护规范

**Files:**

- Modify: `builders/AGENTS.md`
- Reference: `builders/README.md`
- Reference: `builders/Dockerfile.builder-nix`
- Reference: `builders/Dockerfile.builder-win`
- Reference: `builders/Dockerfile.nixcache`
- Reference: `builders/flakes/flake.nix`

**Interfaces:**

- Consumes: 根目录仓库规则及 `builders/` 当前文件结构。
- Produces: 对 `builders/` 全部后续修改生效的维护规范。

- [ ] **Step 1: 写入完整 AGENTS.md**

使用 `apply_patch` 将 `builders/AGENTS.md` 更新为以下章节：

1. 适用范围与目录职责；
2. 构建与检查命令；
3. Dockerfile 和 Nix 风格；
4. 多架构与依赖维护；
5. 分层验证；
6. 密钥与构建产物安全；
7. 提交与变更说明。

文档必须明确：Docker 操作默认遵守根目录规则，优先使用 MCP Docker 工具或远端 Engine API；`flake.nix` 的 nixpkgs revision 与 Dockerfile registry 固定值需要同步；平台例外应使用条件表达式或对应 overlay；README 承载面向使用者的具体运行步骤。

- [ ] **Step 2: 执行静态内容检查**

Run:

```sh
test -s builders/AGENTS.md
rg -n '^#|Docker|Nix|x86_64|aarch64|loongarch64|mips64el|private.key|README.md' builders/AGENTS.md
```

Expected: 文件非空，且所有关键主题均有匹配。

- [ ] **Step 3: 检查敏感内容和陈旧名称**

Run:

```sh
if rg -n 'pgbuilder|nix@123|BEGIN .*PRIVATE KEY' builders/AGENTS.md; then exit 1; fi
```

Expected: 无输出，退出状态为 0。

- [ ] **Step 4: 检查 Markdown 结构与最终差异**

Run:

```sh
rg -n '^## ' builders/AGENTS.md
git diff --check -- builders/AGENTS.md
git diff --stat -- builders/AGENTS.md
```

Expected: 章节齐全，`git diff --check` 无输出；如果文件仍为未跟踪状态，则用 `git diff --no-index /dev/null builders/AGENTS.md` 做等价人工审阅。
