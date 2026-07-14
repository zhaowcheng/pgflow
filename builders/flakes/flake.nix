{
  description = "Multi-architecture build environment for postgresql.";

  # 如修改 nixpkgs-*.url 相关值后请同步更新 Dockerfile 中的 registry 步骤的值。
  inputs = {
    # 2025-05-24: tag 25.05
    nixpkgs-nix.url = "https://ghfast.top/https://github.com/NixOS/nixpkgs/archive/11cb3517b3af6af300dd6c055aeda73c9bf52c48.tar.gz";
    # 2025-12-11: 分支 loong-release-25.11 最新 commit
    nixpkgs-loong.url = "https://ghfast.top/https://github.com/loongson-community/nixpkgs/archive/7b133b90e007e17a02c8f96f366e6f15049259b4.tar.gz";
    # 2016-04-01: tag 16.03，该版本 nixpkgs 中的 glibc 版本为 2.23，是可以兼容 linux kernel 2.6.32 的最高版本。
    nixpkgs-old = {
      url = "https://ghfast.top/https://github.com/NixOS/nixpkgs/archive/d231868990f8b2d471648d76f07e747f396b9421.tar.gz";
      flake = false;  # 这个版本没有 flake 支持
    };
    # 2024-11-14: main 分支最新 commit
    flake-utils.url = "https://ghfast.top/https://github.com/numtide/flake-utils/archive/11707dc2f618dd54ca8739b309ec4fc024de578b.tar.gz";
  };

  outputs = { self, nixpkgs-nix, nixpkgs-loong, nixpkgs-old, flake-utils}:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" "loongarch64-linux" "mips64el-linux" ] (system:
      let
        mips64elLinuxOverlay = import ./overlays/mips64el-linux.nix;
        loongarch64LinuxOverlay = import ./overlays/loongarch64-linux.nix;
        pkgs = import ( if system == "loongarch64-linux" then nixpkgs-loong else nixpkgs-nix ) { 
          # mips64el-linux 上编译 xgcc 时会错误的使用 32 位的头文件，为了避免这类问题，明确为该平台指定 abi 为 64 位。
          system = if system == "mips64el-linux" then "mips64el-linux-gnuabi64" else system;
          overlays =
            if system == "mips64el-linux" then [ mips64elLinuxOverlay ]
            else if system == "loongarch64-linux" then [ loongarch64LinuxOverlay ]
            else [ ];
          config = {
            allowUnsupportedSystem = true;
          };
        };
        pkgsOld = import nixpkgs-old { 
          system = system;
          config = {
            allowBroken = true;
          };
        };
        # 自定义 locale 集，覆盖 PostgreSQL 及相关工具常见的中英文编码场景。
        glibcLocales = pkgs.glibcLocales.override {
          allLocales = false;
          locales = [
            "en_US/ISO-8859-1"
            "en_US.UTF-8/UTF-8"
            "zh_CN/GB2312"
            "zh_CN.GB18030/GB18030"
            "zh_CN.GBK/GBK"
            "zh_CN.UTF-8/UTF-8"
          ];
        };
        scws = pkgs.callPackage ./derivations/scws.nix { };
        scwsOld = pkgsOld.callPackage ./derivations/scws.nix { };
        oraclient = pkgs.lib.optionalAttrs (system != "loongarch64-linux" && system != "mips64el-linux") (pkgs.callPackage ./derivations/oraclient.nix { });
        oraclientOld = pkgsOld.callPackage ./derivations/oraclient.nix { };
        loongson-jdk = pkgs.lib.optionalAttrs (system == "loongarch64-linux") (pkgs.callPackage ./derivations/loongson-jdk.nix { });
      in
      {
        devShells.postgres = pkgs.mkShell {
          name = "postgres";
          buildInputs = [
            # general
            glibcLocales
            pkgs.autoconf
            pkgs.automake
            pkgs.libtool
            pkgs.pkg-config
            pkgs.patchelf
            # postgres
            pkgs.readline
            pkgs.zlib
            pkgs.flex
            pkgs.bison
            pkgs.python3  # plpython/patroni
            pkgs.perl
            pkgs.tcl
            pkgs.openssl
            pkgs.curl
            pkgs.krb5
            pkgs.openldap
            pkgs.pam
            pkgs.lz4
            pkgs.zstd
            pkgs.gettext
            pkgs.libossp_uuid
            pkgs.liburing
            pkgs.numactl
            pkgs.libxslt
            pkgs.libxml2
            pkgs.docbook-xsl-nons
            pkgs.docbook_xml_dtd_45
            pkgs.icu
            pkgs.libselinux
            pkgs.lcov
            pkgs.systemtap-sdt
            pkgs.libsystemtap
            pkgs.perlPackages.IPCRun
            pkgs.perlPackages.TestMore
            pkgs.perlPackages.DataDumper
            pkgs.perlPackages.TestSimple
            # postgis
            pkgs.proj
            pkgs.geos
            pkgs.json_c
            pkgs.sfcgal
            pkgs.pcre2
            pkgs.protobufc
            pkgs.cunit
            pkgs.docbook5
            # zhparser
            scws
            # pgcenter
            pkgs.go
            # pgpool
            pkgs.flex
            pkgs.bison
            pkgs.openssl
            pkgs.openldap
            pkgs.pam
          ] ++ pkgs.lib.optionals (system != "loongarch64-linux" && system != "mips64el-linux") [
            # pg 不支持 loongarch64 的 llvm；mips64el 上 llvm 和 clang 没有编译成功。
            pkgs.llvm
            pkgs.clang
            # postgis 可选库 gdal, dblatex 不支持 loongarch64 和 mips64el。
            pkgs.gdal
            pkgs.dblatex
            # oracle_fdw: oracle 不支持 loongarch64 和 mips64el。
            oraclient
            pkgs.libaio
            # mysql_fdw: mysql 不支持 loongarch64 和 mips64el。
            pkgs.mysql80
            # pgroonga: 依赖库 valgrind 不支持 loongarch64 和 mips64el。
            pkgs.groonga
            pkgs.msgpack
            # java
            pkgs.openjdk
          ] ++ pkgs.lib.optionals (system != "mips64el-linux") [
            # mips64el 上 systemd 没有编译成功。
            pkgs.systemd
            # postgis: gtk2 依赖 systemd，所以在 mips64el 上不可用。
            pkgs.gtk2
            # postgis: imagemagick 依赖链中的 rustc 不支持 mips64el（error: missing bootstrap url for platform mips64el-unknown-linux-gnuabi64）
            pkgs.imagemagick
            # frontend: nodejs 不支持 mips64el。
            pkgs.nodejs
          ] ++ pkgs.lib.optionals (system == "loongarch64-linux") [
            loongson-jdk
          ];

          shellHook = ''
            export SCWS_HOME=${scws}
            ${pkgs.lib.optionalString (system == "x86_64-linux" || system == "aarch64-linux") "export ORACLE_HOME=${oraclient}"}
            export LD_LIBRARY_PATH=${scws}/lib:$LD_LIBRARY_PATH
            ${pkgs.lib.optionalString (system == "x86_64-linux" || system == "aarch64-linux") "export LD_LIBRARY_PATH=${oraclient}:$LD_LIBRARY_PATH"}
            ${pkgs.lib.optionalString (system == "x86_64-linux" || system == "aarch64-linux") "export LD_LIBRARY_PATH=${pkgs.libaio}/lib:$LD_LIBRARY_PATH"}
            ${pkgs.lib.optionalString (system == "x86_64-linux" || system == "aarch64-linux") "export MYSQL_HOME=${pkgs.mysql80}"}
            ${pkgs.lib.optionalString (system == "x86_64-linux" || system == "aarch64-linux") "export LD_LIBRARY_PATH=${pkgs.mysql80}/lib:$LD_LIBRARY_PATH"}
            export GOPROXY=https://mirrors.aliyun.com/goproxy/
          '';
        };

        # cpython 编译环境。
        devShells.cpython = pkgs.mkShell {
          name = "cpython";
          buildInputs = [
            pkgs.autoconf
            pkgs.automake
            pkgs.libtool
            pkgs.pkg-config
            pkgs.bzip2
            pkgs.libffi
            pkgs.xz
            pkgs.mpdecimal
            pkgs.readline
            pkgs.libuuid
            pkgs.ncurses
            pkgs.openssl
            pkgs.sqlite
            pkgs.tcl
            pkgs.zlib
            pkgs.zstd
          ];
        };

        # python 程序打包环境。
        devShells.python = pkgs.mkShell {
          name = "python";
          buildInputs = [
          ];
        };

        # java 程序编译环境。
        devShells.java = pkgs.mkShell {
          name = "java";
          buildInputs = [
          ] ++ pkgs.lib.optionals (system == "x86_64-linux" || system == "aarch64-linux") [
            pkgs.openjdk17
            pkgs.maven
          ] ++ pkgs.lib.optionals (system == "loongarch64-linux") [
            loongson-jdk
          ] ++ pkgs.lib.optionals (system != "mips64el-linux") [
            pkgs.nodejs
          ];
        };

        # go 程序编译环境。
        devShells.go = pkgs.mkShell {
          name = "go";
          buildInputs = [
            pkgs.go
          ];
        };

        # 基础环境，仅包含编译工具链。
        devShells.base = pkgs.mkShell {
          name = "base";
          buildInputs = [
          ];
        };

        # nixpkgs 16.03 仅支持 x86_64 和 aarch64。
        # nixpkgs 16.03 中没有 systemtap 包，所以该环境下不支持 --enable-dtrace 编译参数。
        # x86_64 上 pg18 支持的 configure 参数：--enable-nls --with-perl --with-python --with-tcl --with-lz4 --with-gssapi --with-ldap --with-pam --with-systemd --with-uuid=ossp --with-libxml --with-libxslt --enable-debug --enable-cassert --enable-tap-tests --enable-depend --enable-coverage --enable-profiling --enable-injection-points
        # x86_64 上 pg18 不支持的 configure 参数：--with-llvm --with-ssl=openssl --with-libcurl --with-zstd --with-liburing --with-libnuma --enable-dtrace
        # aarch64 上 pg18 支持的 configure 参数：--enable-nls --with-perl --with-tcl --with-lz4 --with-gssapi --with-ldap --with-pam --with-uuid=ossp --with-libxml --with-libxslt --enable-debug --enable-cassert --enable-tap-tests --enable-depend --enable-coverage --enable-profiling --enable-injection-points
        # aarch64 上 pg18 不支持的 configure 参数：--with-llvm --with-ssl=openssl --with-libcurl --with-zstd --with-liburing --with-libnuma --enable-dtrace --with-python --with-systemd
        devShells.postgresOld = pkgsOld.stdenv.mkDerivation {
          name = "postgres-old";
          buildInputs = [
            # general
            pkgsOld.autoconf
            pkgsOld.automake
            pkgsOld.libtool
            pkgsOld.pkgconfig
            pkgsOld.patchelf
            # postgres
            pkgsOld.readline
            pkgsOld.zlib
            pkgsOld.flex
            pkgsOld.bison
            pkgsOld.perl
            pkgsOld.tcl
            pkgsOld.openssl # 版本为 1.0.2g，低于 pg18 要求的 >= 1.1.1
            pkgsOld.curl # 版本为 7.47.1，低于 pg18 要求的 >= 7.61.0
            pkgsOld.libkrb5
            pkgsOld.openldap
            pkgsOld.pam
            pkgsOld.lz4
            pkgsOld.zstd # 版本为 0.5.1，低于 pg17 和 pg18 要求的 >= 1.4.0
            pkgsOld.gettext
            pkgsOld.libossp_uuid
            # pkgsOld.liburing # missing
            pkgsOld.numactl # configure 时找不到：$PKG_CONFIG --exists --print-errors "numa" Package numa was not found in the pkg-config search path. Perhaps you should add the directory containing `numa.pc' to the PKG_CONFIG_PATH environment variable
            pkgsOld.llvm # 版本为 3.7.1，低于 pg17 要求的 >= 10 和 pg18 要求的 >= 14
            pkgsOld.clang
            pkgsOld.libxslt
            pkgsOld.libxml2
            pkgsOld.docbook_xsl
            pkgsOld.docbook_xml_dtd_45
            pkgsOld.icu
            pkgsOld.libselinux
            pkgsOld.lcov
            pkgsOld.perlPackages.IPCRun
            pkgsOld.perlPackages.TestMore
            pkgsOld.perlPackages.DataDumper
            pkgsOld.perlPackages.TestSimple
            # postgis
            pkgsOld.proj
            pkgsOld.geos
            pkgsOld.json_c
            # pkgsOld.sfcgal # missing
            pkgsOld.pcre2
            pkgsOld.protobufc
            pkgsOld.cunit
            pkgsOld.docbook5
            # mysql_fdw
            # pkgsOld.libmysqlclient # missing
            # zhparser
            scwsOld
            # pgpool
            pkgsOld.flex
            pkgsOld.bison
            pkgsOld.openssl
            pkgsOld.openldap
            pkgsOld.pam
            # pgroonga
            # pkgsOld.groonga # missing
            # pkgsOld.msgpack # missing
            # frontend
            pkgsOld.nodejs
            # oracle_fdw
            oraclientOld # 安装后没有链接到 nix 的 glibc
            pkgsOld.libaio
          ] ++ pkgsOld.lib.optionals (system != "aarch64-linux") [
            # postgis
            pkgsOld.gdal # aarch64: error: unsupported system: aarch64-linux
            pkgsOld.dblatex # aarch64: error: assertion '(((stdenv).isFreeBSD || (stdenv).isDarwin) || (stdenv).cc.isGNU)' failed
            pkgsOld.gtk2 # aarch64: error: assertion '(((stdenv).isFreeBSD || (stdenv).isDarwin) || (stdenv).cc.isGNU)' failed
            pkgsOld.imagemagick # aarch64: error: ImageMagick is not supported on this platform.
            pkgsOld.systemd # aarch64: error: assertion '(stdenv).isLinux' failed
            # pgcenter
            pkgsOld.go # aarch64: error: Unsupported system
            # plpython/patroni
            pkgsOld.python3 # aarch64: error: assertion '(((stdenv).isFreeBSD || (stdenv).isDarwin) || (stdenv).cc.isGNU)' failed
            # java
            pkgsOld.openjdk # aarch64: error: assertion '(((stdenv).isFreeBSD || (stdenv).isDarwin) || (stdenv).cc.isGNU)' failed
          ];
          
          shellHook = ''
            export SCWS_HOME=${scwsOld}
            export ORACLE_HOME=${oraclientOld}
            export LD_LIBRARY_PATH=${scwsOld}/lib:$LD_LIBRARY_PATH
            export LD_LIBRARY_PATH=${oraclientOld}:$LD_LIBRARY_PATH
            export LD_LIBRARY_PATH=${pkgsOld.libaio}/lib:$LD_LIBRARY_PATH
            export GOPROXY=https://mirrors.aliyun.com/goproxy/
          '';
        };

        devShells.patchelf = pkgs.stdenv.mkDerivation {
          name = "patchelf";
          buildInputs = [
            pkgs.autoconf
            pkgs.automake
          ];

          # 静态编译
          CFLAGS = "-static";
          LDFLAGS = "-static";
        };
      }
    );
}
