# builders 子目录协作指南

## 适用范围

本文件适用于 `builders/` 及其全部子目录，并继承仓库根目录 `AGENTS.md` 的通用规则。这里维护 pgflow 流水线使用的 Linux、Windows 编译环境和 Nix 二进制缓存镜像，不放置流水线 Python 代码。

面向使用者的镜像构建、启动步骤以 `README.md` 为准；本文件只规定修改这些文件时应遵守的边界、验证方法和安全要求。命令默认从 `builders/` 目录执行。

## 目录结构与职责

- `Dockerfile.builder-nix`：Linux/Nix 多架构编译环境，预构建 `postgres`、`cpython`、`python`、`go`、`java`、`base` 等 dev shell。
- `Dockerfile.builder-win`：Windows 编译环境。修改基础镜像或构建命令时要同时说明支持的 Windows 版本和 `process`、`hyperv` 隔离限制。
- `Dockerfile.nixcache`：Nix 二进制缓存及 SSH 上传服务。缓存协议、签名密钥和认证方式的修改会同时影响 builder 镜像与运行命令。
- `flakes/flake.nix`：各目标系统的公共包集合和 dev shell 定义。
- `flakes/overlays/`：仅存放特定架构需要的 nixpkgs 修正；通用依赖不要放入架构 overlay。
- `flakes/derivations/`：上游 nixpkgs 缺失或不适用时使用的自定义包定义。
- `keys/nix-serve/`：缓存签名材料。私钥属于本地敏感文件，不是普通源码。

不要把下载文件、Docker 导出包、Nix `result` 链接、构建日志或临时缓存加入源码。Nix 命令可能生成 `flake.lock`；除非变更明确要求引入锁文件，否则检查后应保持工作区不新增该文件。

## 构建与检查命令

Docker 操作遵循根目录规则：在用户工作区默认使用 MCP 连接的 Docker 工具或远端 Docker Engine API，不优先调用本机 `docker` CLI。`README.md` 中的 CLI 示例用于说明等价参数；实际执行时应保留相同的构建上下文、Dockerfile、网络、镜像名和隔离模式。

当前约定的名称如下：

- Docker 网络：`pgflow-net`；
- Linux builder 镜像：`pgflow-builder-nix`；
- Windows builder 镜像：`pgflow-builder-win`；
- 缓存镜像和容器：`pgflow-nixcache`。

修改命名时，要同步检查全部 Dockerfile、`README.md`、`env.yml` 及流水线中的引用，不保留迁移前的旧名称。

有可用 Nix 环境和网络时，可先做不构建产物的求值检查：

```sh
nix flake metadata --no-write-lock-file ./flakes
nix flake show --all-systems --no-write-lock-file ./flakes
```

验证某个实际环境时，使用明确的 system 和 dev shell，例如：

```sh
nix develop --no-write-lock-file ./flakes#devShells.x86_64-linux.base -c true
nix develop --no-write-lock-file ./flakes#devShells.aarch64-linux.postgres -c true
```

不要把全架构、全 dev shell 的镜像重建作为文档或单一 derivation 修改的默认验证；按变更影响逐层扩大范围。

## Dockerfile 与 Nix 编写约定

Dockerfile 修改保持现有风格：

- 注释使用中文，说明步骤目的和不直观的兼容性原因；
- Debian 的 `apt update` 与对应的 `apt install` 保持在同一层；
- 版本、下载 URL 和校验信息集中在相关安装步骤附近，升级时一并核对；
- `COPY` 路径相对 `builders/` 构建上下文，不假设从仓库根目录或其他目录构建；
- 影响镜像缓存的稳定步骤放在前面，频繁变化的源码或配置放在后面；
- 不用关闭校验、扩大权限或永久禁用测试来掩盖构建失败，确需例外时写明平台和原因。

Nix 文件保持两空格缩进、属性结尾分号和现有 `let ... in` 结构。依赖优先放在对应 dev shell；仅一个平台需要的包或规避项使用 `pkgs.lib.optionals`、`optionalAttrs` 或对应架构 overlay，不要污染其他平台。

`flake.nix` 中 `nixpkgs-nix` 的固定 revision 与 `Dockerfile.builder-nix`、`Dockerfile.nixcache` 中注册的默认 nixpkgs revision 必须保持一致。修改任一处时，应搜索并同步其余位置：

```sh
rg -n 'nixpkgs/archive|nix registry add|nixpkgs-nix\.url' .
```

自定义 derivation 应明确 `pname`、`version`、每个架构的来源与哈希、构建依赖、安装结果和许可证等元数据。新增二进制来源时必须使用固定版本及哈希，不使用浮动的 latest URL。

## 多架构维护要求

当前 Linux flake 覆盖 `x86_64-linux`、`aarch64-linux`、`loongarch64-linux`、`mips64el-linux`。修改公共环境时必须逐一判断四个平台是否可求值，不能依据 x86_64 成功就默认其他架构可用。

- x86_64 和 aarch64 通常使用主 `nixpkgs-nix` 输入。
- loongarch64 使用专用 nixpkgs 输入及 `loongarch64-linux.nix` overlay。
- mips64el 使用 `mips64el-linux-gnuabi64` system 映射及专用 overlay。
- Oracle Client、LLVM、systemd、Node.js 等已有平台限制应继续通过条件依赖表达。
- QEMU 下跳过或标记预期失败的测试必须限定到对应 overlay，并保留具体失败原因；不要把规避项提升为所有平台的默认行为。

调整平台列表、dev shell 名称或容器中预构建的 shell 时，要同步更新 `Dockerfile.builder-nix` 的 `nix develop` 步骤以及依赖这些名称的流水线配置。

## 测试与验证

按风险选择最小但充分的验证范围：

1. 仅修改 Markdown：检查命令、文件名、镜像名和网络名，并运行 `git diff --check`。
2. 修改单个 derivation：执行相关 Nix 求值，并至少构建或进入一个实际使用该 derivation 的 dev shell。
3. 修改架构 overlay：验证对应 system；涉及工具链或公共依赖时，再验证一个不使用该 overlay 的 system，防止条件泄漏。
4. 修改 `flake.nix` 公共依赖或 nixpkgs revision：求值全部四个平台，并验证受影响 dev shell；确认 Dockerfile 中的 revision 已同步。
5. 修改 Dockerfile：通过 MCP Docker 工具或远端 Engine API 构建受影响镜像，检查关键命令可运行。涉及缓存服务时还要验证 builder 能拉取缓存及上传路径可用。
6. 修改 Windows 镜像：记录 Host/基础镜像版本和使用的隔离模式；未在 Windows Docker Engine 上实测时必须明确说明。

高成本的全镜像、全架构构建只在公共工具链、平台列表、缓存配置或发布前验证时执行。变更说明中列出已验证和未验证的平台，不用推测代替结果。

## 安全与配置

- 禁止读取、打印、复制到日志或提交 `keys/nix-serve/private.key` 的内容；检查文件存在性时只使用路径或元数据。
- 公钥可以按部署需要分发，但更换密钥对时必须同步缓存服务与 builder 的 trusted public key。
- 不在 Dockerfile、README 或提交说明中新增真实密码、令牌、私有地址和内部镜像凭据。现有历史配置不代表可以继续复制硬编码凭据。
- 修改缓存认证方式时，优先使用构建 secret、运行时挂载或目标环境的秘密管理机制，并说明兼容与迁移步骤。
- 日志和验证输出只保留错误附近的必要片段；不得为了排障输出环境中的完整配置或密钥文件。

## 提交与变更说明

提交标题使用简短中文祈使句，例如 `更新 Nix 编译环境依赖`、`修复 mips64el overlay 构建`。不要把镜像导出文件、缓存、密钥或无关格式化混入功能变更。

PR 或变更说明至少包含：受影响的 Dockerfile、flake/dev shell、目标架构、nixpkgs revision 或关键版本、实际执行的验证、生成的镜像名，以及未验证的平台或 Windows 隔离模式。若使用者命令或名称发生变化，同时更新 `README.md`。
