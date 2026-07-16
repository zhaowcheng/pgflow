# Rocky Linux 9 PostgreSQL Builder 设计

## 目标

新增 `builders/Dockerfile.builder-el9`，提供基于 Rocky Linux 9 的通用 PostgreSQL 编译和回归测试环境。同一镜像应支持 PostgreSQL 14 及以上版本执行 `make world` 和 `make check-world`，但不在镜像构建阶段下载或编译 PostgreSQL 源码。

基础镜像固定为：

```text
192.168.95.251:8082/hiflow-docker-group/library/rockylinux:9
```

## 镜像内容

Dockerfile 启用 Rocky Linux 9 CRB 仓库，安装 Development Tools 工具组，并显式安装 PostgreSQL 完整构建所需的依赖，包括：

- GCC、Make、Flex、Bison 等基础编译工具；
- Readline、Zlib、OpenSSL、ICU、XML、XSLT、LZ4、Zstd 等库及开发文件；
- LDAP、PAM、systemd、UUID、Kerberos 等可选功能的开发文件；
- Python、Tcl、Perl，以及回归测试使用的 Perl `IPC::Run`；
- DocBook 等 `make world` 所需的文档工具；
- Git、下载、归档、补丁和进程检查等日常构建辅助工具。

所有系统包在一个构建层中安装，并在该层末尾清理 DNF 缓存，避免保留无用的软件包元数据。

## Locale 与运行身份

镜像生成并默认使用 `en_US.UTF-8`，确保 PostgreSQL 初始化和回归测试具备稳定的 UTF-8 locale。

系统包安装完成后创建普通用户 `hiflow`：

- home 目录为 `/home/hiflow`；
- 登录 Shell 为 Bash；
- 不授予 sudo 权限；
- Dockerfile 的默认用户为 `hiflow`；
- 默认工作目录为 `/home/hiflow`。

容器默认命令为 Bash，便于挂载或拉取任意 PostgreSQL 14+ 源码后执行配置、编译和测试。

## 验证

先用静态检查确认基础镜像、关键依赖、CRB、locale、`hiflow` 用户、工作目录、默认用户、缓存清理和 Bash 默认命令均存在。随后优先通过 MCP 连接的 Docker 服务或远端 Docker Engine API 构建镜像，并在容器中检查用户、工作目录、locale 和关键工具。

若当前没有可用的 Docker 连接，则完成静态验证并明确记录镜像构建与 PostgreSQL `make world`、`make check-world` 尚未实测，不以推测替代结果。
