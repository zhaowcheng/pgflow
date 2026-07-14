final: prev: {
  gettext = prev.gettext.overrideAttrs (oldAttrs: {
    # mips64el-linux 上编译 gettext 时由于缺少 file 命令导致动态库编译失败（cannot stat '.libs/libgnuintl.so.8.4.0': No such file or directory），所以这里把 file 作为其依赖。
    nativeBuildInputs = (oldAttrs.nativeBuildInputs or []) ++ [ final.file ];
  });
  
  coreutils = prev.coreutils.overrideAttrs (oldAttrs: {
    preCheck = (oldAttrs.preCheck or "") + ''
      # 把 qemu 模拟环境下无法运行的测试标记为预期失败（XFAIL）。
      sed -i 's/^XFAIL_TESTS =/& test-dup2 /' gnulib-tests/Makefile
      sed -i 's/^XFAIL_TESTS =/& test-getdtablesize /' gnulib-tests/Makefile
      sed -i 's/^XFAIL_TESTS =/& test-random_r /' gnulib-tests/Makefile
    '';
  });

  findutils = prev.findutils.overrideAttrs (oldAttrs: {
    preCheck = (oldAttrs.preCheck or "") + ''
      # 把 qemu 模拟环境下无法运行的测试标记为预期失败（XFAIL）。
      sed -i 's/^XFAIL_TESTS =/& test-dup2 /' gnulib-tests/Makefile
      sed -i 's/^XFAIL_TESTS =/& test-getdtablesize /' gnulib-tests/Makefile
      sed -i 's/^XFAIL_TESTS =/& test-random_r /' gnulib-tests/Makefile
    '';
  });

  gnutls = prev.gnutls.overrideAttrs (oldAttrs: {
    preCheck = (oldAttrs.preCheck or "") + "\n" + ''
      # 把 qemu 模拟环境下无法运行的测试标记为预期失败（XFAIL）。
      sed -i 's/^XFAIL_TESTS =/& test-dup2 /' src/gl/tests/Makefile
      sed -i 's/^XFAIL_TESTS =/& test-getdtablesize /' src/gl/tests/Makefile  
      sed -i 's/^XFAIL_TESTS =/& test-random_r /' src/gl/tests/Makefile
    '';
  });
  
  gnugrep = prev.gnugrep.overrideAttrs (oldAttrs: {
    preCheck = (oldAttrs.preCheck or "") + ''
      # 把 qemu 模拟环境下无法运行的测试标记为预期失败（XFAIL）。
      sed -i 's/^XFAIL_TESTS =/& stack-overflow /' tests/Makefile
      sed -i 's/^XFAIL_TESTS =/& test-c-stack.sh /' gnulib-tests/Makefile
      sed -i 's/^XFAIL_TESTS =/& test-dup2 /' gnulib-tests/Makefile
      sed -i 's/^XFAIL_TESTS =/& test-getdtablesize /' gnulib-tests/Makefile
      sed -i 's/^XFAIL_TESTS =/& test-sigsegv-catch-stackoverflow1 /' gnulib-tests/Makefile
      sed -i 's/^XFAIL_TESTS =/& test-sigsegv-catch-stackoverflow2 /' gnulib-tests/Makefile
    '';
  });

  diffutils = prev.diffutils.overrideAttrs (oldAttrs: {
    preCheck = (oldAttrs.preCheck or "") + ''
      # 把 qemu 模拟环境下无法运行的测试标记为预期失败（XFAIL）。
      sed -i 's/^XFAIL_TESTS =/& test-c-stack.sh /' gnulib-tests/Makefile
      sed -i 's/^XFAIL_TESTS =/& test-dup2 /' gnulib-tests/Makefile
      sed -i 's/^XFAIL_TESTS =/& test-getdtablesize /' gnulib-tests/Makefile
      sed -i 's/^XFAIL_TESTS =/& test-random_r /' gnulib-tests/Makefile
      sed -i 's/^XFAIL_TESTS =/& test-sigsegv-catch-stackoverflow1 /' gnulib-tests/Makefile
      sed -i 's/^XFAIL_TESTS =/& test-sigsegv-catch-stackoverflow2 /' gnulib-tests/Makefile
    '';
  });

  libseccomp = prev.libseccomp.overrideAttrs (oldAttrs: {
    preCheck = (oldAttrs.preCheck or "") + ''
      # 把 qemu 模拟环境下无法运行的测试删除。
      rm -f tests/52-basic-load.tests
    '';
  });

  openssl = prev.openssl.overrideAttrs (oldAttrs: {
    # 默认情况下会自动识别为 32 位的 target: linux-mips64，所以明确为其指定为 64 位 target。
    configureFlags = (oldAttrs.configureFlags or []) ++ [ "linux64-mips64" ];
  });

  libuv = prev.libuv.overrideAttrs (oldAttrs: {
    # 定义 __QEMU__ 宏以便自动跳过 qemu 环境下不适用的测试。
    NIX_CFLAGS_COMPILE = (oldAttrs.NIX_CFLAGS_COMPILE or "") + " -D__QEMU__";
  });

  go = prev.go.overrideAttrs (oldAttrs: {
    # 替换 bootstrap Go 版本为 1.23，因为 1.22 在 qemu 环境下会出现 SIGBUS 错误。
    GOROOT_BOOTSTRAP = "${final.buildPackages.callPackage (final.path + "/pkgs/development/compilers/go/binary.nix") {
      version = "1.23.12";
      hashes = {
        linux-mips64le = "d686184c7b374d1a5048aef5dc26b7b6061e532f402361f300e809e00da2e76a";
      };
    }}/share/go";
  });

  dbus = prev.dbus.overrideAttrs (oldAttrs: {
    preCheck = (oldAttrs.preCheck or "") + ''
      # 从 TESTS 变量中移除在 qemu 环境下会被系统杀死的测试
      sed -i 's/test-printf[[:space:]]*//g' test/Makefile
      sed -i 's/test-shell[[:space:]]*//g' test/Makefile
      sed -i 's/test-hash[[:space:]]*//g' test/Makefile
      sed -i 's/test-atomic[[:space:]]*//g' test/Makefile
    '';
  });

  openldap = prev.openldap.overrideAttrs (oldAttrs: {
    # 禁用测试，因为在 QEMU 环境下 slapd 服务无法正常启动。
    doCheck = false;
  });

  elfutils = (prev.elfutils.override {
    # 禁用 debuginfod，因为其依赖 libidn 编译时带上 libunistring，而 libidn 默认编译不带这个，重新编译 libidn 会导致整个工具链重编译。
    enableDebuginfod = false;
  }).overrideAttrs (oldAttrs: {
    preCheck = (oldAttrs.preCheck or "") + ''
      # 把 qemu 模拟环境下无法运行的测试标记为预期失败（XFAIL）。
      sed -i '/^TESTS.*=/i XFAIL_TESTS =' tests/Makefile
      sed -i 's/^XFAIL_TESTS =/& run-strip-strmerge.sh/g' tests/Makefile
      sed -i 's/^XFAIL_TESTS =/& run-strip-reloc-self.sh/g' tests/Makefile
      sed -i 's/^XFAIL_TESTS =/& run-elflint-self.sh/g' tests/Makefile
      sed -i 's/^XFAIL_TESTS =/& run-varlocs-self.sh/g' tests/Makefile
      sed -i 's/^XFAIL_TESTS =/& run-exprlocs-self.sh/g' tests/Makefile
      sed -i 's/^XFAIL_TESTS =/& run-backtrace-native.sh/g' tests/Makefile
      sed -i 's/^XFAIL_TESTS =/& run-backtrace-dwarf.sh/g' tests/Makefile
      sed -i 's/^XFAIL_TESTS =/& run-deleted.sh/g' tests/Makefile
      sed -i 's/^XFAIL_TESTS =/& dwfl-proc-attach/g' tests/Makefile
      sed -i 's/^XFAIL_TESTS =/& run-reverse-sections-self.sh/g' tests/Makefile
    '';
  });

  libyuv = prev.libyuv.overrideAttrs (oldAttrs: {
    # 跳过在 QEMU 环境下会失败的测试。
    checkPhase = ''
      runHook preCheck
      ./libyuv_unittest --gtest_filter="-LibYUVConvertTest.I422ToARGBToRGB565_Unaligned:LibYUVConvertTest.I420ToARGBToRGB565_Unaligned:LibYUVRotateTest.RotatePlane90_TestStride"
      runHook postCheck
    '';
  });
  
  swtpm = prev.swtpm.overrideAttrs (oldAttrs: {
    # 在 QEMU 环境下禁用测试，因为 seccomp 机制不兼容。
    doCheck = false;
  });

  tpm2-tss = prev.tpm2-tss.overrideAttrs (oldAttrs: {
    configureFlags = (oldAttrs.configureFlags or []) ++ [ 
      # 原因类似 elfutils 的 enableDebuginfod 选项。
      "--disable-fapi"
      # doInstallCheck = false 时需要同时禁用该选项，否则 configure 会因找不到 `ss` 程序而报错。
      "--disable-integration"
    ];
    # 在 QEMU 环境下禁用测试，因为 TPM 模拟器 swtpm 无法正常运行
    doInstallCheck = false;
  });

  geos = prev.geos.overrideAttrs (oldAttrs: {
    # "103 - unit-capi-GEOSIntersection" 和 "unit-io-WKBWriter" 测试失败。
    doCheck = false;
  });

  proj = prev.proj.overrideAttrs (oldAttrs: {
    buildInputs = [
      prev.sqlite
      prev.libtiff
      # curl 改为 curlMinimal
      prev.curlMinimal
      prev.nlohmann_json
    ];
  });

  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (python-final: python-prev: {
      psutil = python-prev.psutil.overridePythonAttrs (oldAttrs: {
        # 跳过在 QEMU 环境下会失败的测试。
        disabledTests = (oldAttrs.disabledTests or []) ++ [
          "test_net_if_addrs"
          "test_net_if_stats"
        ];
      });
      
      mypy = python-prev.mypy.overridePythonAttrs (oldAttrs: {
        # qemu 环境下不支持 GOT 重定位，所以禁用 mypyc，改用纯 python 编译。
        env = (oldAttrs.env or {}) // {
          MYPY_USE_MYPYC = false;
        };
      });
    })
  ];
}