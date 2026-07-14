本项目用于构建 PostreSQL 及其相关工具的编译环境，主要文件如下（其他文件均是构建相关镜像所需的，具体说明请查看 Dockerfile 中对应地方的注释。）：
- **Dockerfile.builder-nix**: Nix 编译环境。
- **Dockerfile.builder-win**: Windows 编译环境。
- **Dockerfile.nixcache**: Nix 二进制缓存服务。

## 1. Nix 编译环境构建

首次使用先执行如下命令：
```console
# 创建 binfmt，用于 x86_64 上运行其他架构的软件。
$ docker run --name binfmt --restart=always --privileged tonistiigi/binfmt --install all

# 创建便于容器间互相使用名称访问的网路。
$ docker network create pgflow-net

# 创建 nix 缓存服务（建议定期执行 docker commit pgflow-nixcache pgflow-nixcache 保存缓存容器）。
$ docker build -t pgflow-nixcache -f Dockerfile.nixcache .
$ docker run -d --name pgflow-nixcache --network pgflow-net --restart=always pgflow-nixcache
```

然后在当前目录执行如下命令构建编译环境（每当编译环境有变更后也只需从这里开始运行）：
```console
$ DOCKER_BUILDKIT=0 docker build --network pgflow-net -t pgflow-builder-nix -f Dockerfile.builder-nix .
```

构建成功后使用如下命令运行编译环境：
```console
$ docker run -it --network pgflow-net --rm --privileged pgflow-builder-nix bash
```

当第一次构建完成编译环境后或者后续有新的构建时，建议执行如下命令上传缓存（密码请查看 Dockerfile.nixcache）：
```console
$ nix copy --all --to ssh://root@pgflow-nixcache 
```

## 2. Windows 编译环境构建

Windows 容器有两种模式，在构建镜像和启动容器时均可通过 `--isolation` 参数指定，在 Windows Server 上通常默认是 process，Windows 10/11 Docker Desktop 上通常默认是 hyperv 模式：
- `process` 隔离：容器与 Docker Host 共用 Windows 内核，启动更快、开销更低，但要求 Docker Host 与基础镜像 Windows 版本兼容，即 `build number` 相同，可以通过 powershell 命令 `[System.Environment]::OSVersion.Version` 查询得到。建议优先选择该模式，如果得到 `The operating system of the container does not match the operating system of the host` 这样的错误则说明不兼容，再改用 hyperv 模式。
- `hyperv` 隔离：容器运行在轻量 Hyper-V VM 中，镜像与 Host 版本兼容性更宽松，但启动和资源开销更高。

构建 Windows 编译环境镜像：
```console
$ docker build --isolation=process -t pgflow-builder-win -f Dockerfile.builder-win .
```

启动 Windows 编译环境容器：
```console
$ docker run -it --rm --isolation=process pgflow-builder-win
```
