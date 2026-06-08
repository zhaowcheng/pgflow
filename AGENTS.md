# Repository Guidelines

## 项目结构与模块组织

本仓库是基于 `xflow.framework` 的 PostgreSQL 生态打包流水线项目。核心代码在 `pipelines/`，公共打包逻辑在 `pipelines/common/`，远端节点上执行的 shell 辅助脚本在 `scripts/`。

- `pipelines/pack_postgres.py`：PostgreSQL 主包打包流程。
- `pipelines/pack_*.py`：PostGIS、pgvector、pgpool、FDW、zhparser、Patroni 等扩展或工具的打包流程。
- `pipelines/common/pack.py`：打包基类，封装 Nix 环境、归档、依赖拷贝、RPATH/interpreter 处理。
- `pipelines/common/scripts.py`：把 Python 流水线调用转发到 `scripts/*.sh`。
- `env.yml`：xflow 节点和 Docker 服务配置，包含远端工作目录、SSH、容器节点等信息。
- `requirements.txt`：Python 依赖，目前要求 Python 3.10+，依赖 `xflow.framework` 和 `typing_extensions`。
- `workdir/`、`venv/`、`__pycache__/`：本地运行产物或环境目录，不应作为功能代码修改。

## 构建、运行与开发命令

建议在已有虚拟环境中运行；如需重建环境，使用 Python 3.10+：

```sh
python3 -m venv venv
venv/bin/pip install -r requirements.txt
```

查看 xflow 顶层命令：

```sh
venv/bin/xflow -p . --help
```

运行具体流水线时使用 `xflow -p . run <pipeline>`，并按对应 `Options` 补齐参数，例如 `repo_url`、`revision`、`system`、`nix_flakes_dir`、`pg_pkg_url` 等。实际构建依赖 `env.yml` 中可访问的节点、远端 Nix flakes 目录和目标架构 shell。

注意：当前 `xflow -p . run --help` 会尝试导入所有流水线；如果 `pipelines/pack_patroni.py` 中类名仍不是 `pack_patroni`，该帮助命令会因模块类名不匹配失败。

## 代码风格与命名约定

Python 代码遵循现有风格：四空格缩进，类型注解明确，流水线类名与文件名保持一致，例如 `pipelines/pack_pgvector.py` 中定义 `class pack_pgvector(...)`。新增流水线优先继承现有基类：

- 普通打包流程继承 `pack`。
- C/C++ 程序继承 `pack_c`。
- 需要 PostgreSQL 包的生态组件继承 `pack_pgceco`。
- PostgreSQL 扩展继承 `pack_pgext`。
- Python 程序继承 `pack_python`。

每个流水线通常包含内部 `Options` 类、`setup()`、`stage1()`、`stage2()`、`stage3()`、`teardown()` 和 `version`。`Options` 使用 `Pipeline.Option(...)` 声明参数；默认值、choices 和 validator 应放在对应流水线内，避免污染公共基类。

注释和 docstring 以中文为主，说明阶段目的、参数含义和架构差异。不要把具体版本、URL、构建参数硬编码到公共基类，除非它确实是所有包共享的规则。

## 打包逻辑注意事项

远端命令通过 `self.node.exec(...)`、`self.node.git(...)`、`self.node.putfile(...)`、`self.node.getfile(...)` 执行。涉及目标节点路径时优先使用 `PurePosixPath` 或 `self.node.cwd.joinpath(...)`，不要使用本机路径拼接假设远端环境。

进入 Nix 编译环境应使用 `with self.nixenv():`，不要在各流水线里重复拼接 `nix develop` 命令。C/C++ 包依赖处理应复用 `handle_deps()`、`copy_deps()`、`set_rpath()`、`set_interp()`，避免手写重复的 `patchelf` 逻辑。

归档文件名由 `pkgstem` 统一生成，通常包含程序名、版本、目标系统和 glibc 版本。修改命名规则前要确认下游下载、安装或发布流程是否依赖现有格式。

## 测试与验证指南

仓库没有独立测试套件。较小的 Python 改动至少做语法检查：

```sh
venv/bin/python -m compileall pipelines
```

修改流水线参数、类名或导入关系后，验证 xflow 能导入目标流水线：

```sh
venv/bin/xflow -p . --help
```

涉及实际构建逻辑时，应在目标节点上运行受影响的流水线，至少覆盖变更涉及的 `system`。公共基类、依赖处理、RPATH 或 interpreter 逻辑变更风险较高，应优先验证 PostgreSQL 主包和一个 PostgreSQL 扩展包。

## 提交与 PR 规范

提交标题保持简短、具体，优先使用中文祈使句，例如 `修复 patroni 流水线类名`、`增加 pgvector 打包参数`。避免把格式化、环境文件、构建产物和功能变更混在同一提交。

PR 或变更说明应包含：影响的流水线、目标架构、关键参数、已执行的验证命令、生成的包名，以及仍未验证的远端节点或架构限制。

## 安全与配置提示

`env.yml` 可能包含内网地址、用户名、密码、Docker 服务信息。不要把真实凭据、个人节点、临时缓存地址或私有下载链接提交到仓库。处理 `repo_url`、`pg_pkg_url` 等外部输入时，保持参数化，避免在公共代码中固定个人镜像或代理地址。

`workdir/` 中的 `buildid.txt`、锁文件、下载包和构建目录属于运行状态，不要依赖它们作为源码事实，也不要把临时产物纳入提交。
