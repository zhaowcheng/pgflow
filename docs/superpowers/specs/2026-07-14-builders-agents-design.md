# builders/AGENTS.md 设计说明

## 目标

为 `builders/` 生成一份完整但不重复 `README.md` 的维护规范，使后续修改 Docker 构建环境、Nix flake、跨架构 overlay 和自定义 derivation 时有明确边界、验证方法与安全要求。

## 文档范围

`builders/AGENTS.md` 适用于 `builders/` 及其全部子目录，并继承仓库根目录 `AGENTS.md` 的通用规则。文档重点覆盖：

- `Dockerfile.builder-nix`、`Dockerfile.builder-win`、`Dockerfile.nixcache` 的职责；
- `flakes/flake.nix`、`flakes/overlays/`、`flakes/derivations/` 的修改边界；
- x86_64、aarch64、loongarch64、mips64el 的平台差异；
- Docker 镜像、容器和网络名称的一致性；
- Nixpkgs revision、Dockerfile registry 与 flake 输入的同步约束；
- 密钥、密码、缓存地址及构建产物的安全规则；
- 从静态检查到目标架构实构建的分层验证方法。

## 内容结构

生成的文档采用以下章节：

1. 子目录职责与文件组织；
2. 常用构建和检查命令；
3. Dockerfile 与 Nix 代码风格；
4. 多架构及依赖维护约束；
5. 测试与验证要求；
6. 安全、密钥和构建产物规则；
7. 提交与变更说明要求。

具体操作步骤仍以 `builders/README.md` 为准，`AGENTS.md` 只保留维护代码所需的命令和约束，避免两份文档长期重复。

## 验证标准

- 文档内容与当前目录名、文件名、镜像名及网络名一致；
- 不读取或输出 `keys/nix-serve/private.key` 的内容；
- 不把全架构 Docker 构建规定为所有改动的默认验证；
- 明确要求公共环境或 revision 变更进行同步检查；
- Markdown 标题、代码块和列表结构完整，所有要求均已明确。
