{
  description = "Multi-architecture build environment for postgresql.";

  # 如修改 nixpkgs-*.url 相关值后请同步更新 Dockerfile 中的 registry 步骤的值。
  inputs = {
    # 2025-05-24: tag 25.05
    nixpkgs-nix.url = "https://ghfast.top/https://github.com/NixOS/nixpkgs/archive/11cb3517b3af6af300dd6c055aeda73c9bf52c48.tar.gz";
    # 2025-12-11: 分支 loong-release-25.11 最新 commit
    nixpkgs-loong.url = "https://ghfast.top/https://github.com/loongson-community/nixpkgs/archive/7b133b90e007e17a02c8f96f366e6f15049259b4.tar.gz";
    # 2024-11-14: main 分支最新 commit
    flake-utils.url = "https://ghfast.top/https://github.com/numtide/flake-utils/archive/11707dc2f618dd54ca8739b309ec4fc024de578b.tar.gz";
  };

  outputs = { self, nixpkgs-nix, nixpkgs-loong, flake-utils}:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" "loongarch64-linux" ] (system:
      let
        loongarch64LinuxOverlay = import ./overlays/loongarch64-linux.nix;
        pkgs = import ( if system == "loongarch64-linux" then nixpkgs-loong else nixpkgs-nix ) { 
          inherit system;
          overlays =
            if system == "loongarch64-linux" then [ loongarch64LinuxOverlay ]
            else [ ];
          config = {
            allowUnsupportedSystem = true;
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
        oraclient = pkgs.lib.optionalAttrs (system != "loongarch64-linux") (pkgs.callPackage ./derivations/oraclient.nix { });
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
            pkgs.systemd
            pkgs.gtk2
            pkgs.imagemagick
            pkgs.nodejs
          ] ++ pkgs.lib.optionals (system != "loongarch64-linux") [
            # pg 不支持 loongarch64 的 llvm。
            pkgs.llvm
            pkgs.clang
            # postgis 可选库 gdal, dblatex 不支持 loongarch64。
            pkgs.gdal
            pkgs.dblatex
            # oracle_fdw: oracle 不支持 loongarch64。
            oraclient
            pkgs.libaio
            # mysql_fdw: mysql 不支持 loongarch64。
            pkgs.mysql80
            # pgroonga: 依赖库 valgrind 不支持 loongarch64。
            pkgs.groonga
            pkgs.msgpack
            # java
            pkgs.openjdk
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
            pkgs.nodejs
          ] ++ pkgs.lib.optionals (system == "loongarch64-linux") [
            loongson-jdk
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
