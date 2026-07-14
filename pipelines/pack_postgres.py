from functools import cached_property
from pathlib import PurePosixPath
from typing_extensions import Self

from xflow.framework.pipeline import Pipeline
from .common.pack import pack_c
from .common.scripts import copy_perl, copy_python, copy_tcl, wrap_envs

from pydantic import model_validator


class pack_postgres(pack_c):
    """
    postgres 打包流程。
    """
    class Options(pack_c.Options):
        """
        流水线参数表。
        """
        repourl: str = Pipeline.Option(desc='Repository URL.',
                                       default='https://github.com/postgres/postgres.git')
        progname: str = Pipeline.Option(desc='Program name.',
                                        default='postgres')
        nix_env_name: str = Pipeline.Option(desc='Nix shell environment name.',
                                            default='postgres')
        include_tests: bool = Pipeline.Option(desc='Include PostgreSQL regression tests.',
                                              default=True)
        
        @model_validator(mode='after')
        def default_configure_options(self) -> Self:
            """
            默认 configure 参数。
            """
            if not self.configure_options:
                self.configure_options = '--enable-nls ' \
                                         '--enable-tap-tests ' \
                                         '--with-perl ' \
                                         '--with-python ' \
                                         '--with-tcl ' \
                                         '--with-lz4 ' \
                                         '--with-zstd ' \
                                         '--with-openssl ' \
                                         '--with-gssapi ' \
                                         '--with-ldap ' \
                                         '--with-pam ' \
                                         '--with-ossp-uuid ' \
                                         '--with-libnuma ' \
                                         '--with-liburing ' \
                                         '--with-libxml ' \
                                         '--with-libxslt ' \
                                         '--with-selinux ' \
                                         '--with-systemd ' \
                                         '--with-libcurl '
                if self.system not in ['loongarch64-linux']:
                    self.configure_options += '--with-llvm '
            return self

    def setup(self) -> None:
        """
        前置步骤。
        """
        self.options: __class__.Options  # 保留用于自动提示
        super().setup()

        self.configure_options = (self.options.configure_options or '') + f' --prefix={self.instdir}'
        self.testpackdir = self.node.cwd.joinpath('test_package')
        self.testsdir = self.testpackdir

    def stage1(self) -> None:
        """
        拉取代码。
        """
        options = ''
        if self.options.revision:
            options = f'--branch {self.options.revision} --depth 1'
        self.node.git(self.options.repourl,
                      self.options.revision,
                      directory=self.codedir,
                      options=options)
        with self.nixenv():
            self.node.exec_script('scripts/patch_pg_regress_shell.py',
                                  argstr=f'{self.codedir}')
        
    def stage2(self) -> None:
        """
        编译。
        """
        with self.node.dir(self.codedir):
            with self.nixenv():
                self.node.exec(f'./configure {self.configure_options}')
                self.node.exec('make world -j`nproc`')
                if self.options.include_tests:
                    self.node.exec('make -C src/interfaces/libpq/test all')
                    self.node.exec('make -C src/interfaces/ecpg/test all')
                self.node.exec('make install-world')

    def stage3(self) -> None:
        """
        打包。
        """
        self.copy_deps()
        self.copy_instscript(self.packdir)
        self.archive(self.packdir, self.pkgname)
        if self.options.include_tests:
            self.copy_tests()
            self.archive(self.testpackdir, self.test_pkgname)

    def copy_tests(self) -> None:
        """
        复制 PostgreSQL 回归测试树、测试工具和包内测试入口。
        """
        test_srcdir = self.testsdir.joinpath('src')
        self.node.exec(f'mkdir -p {test_srcdir}')
        with self.node.dir(self.codedir):
            self.node.exec(f'tar '
                           f'--exclude=.git '
                           f'--exclude="*.c" '
                           f'--exclude=tmp_check '
                           f'--exclude=tmp_install '
                           f'--exclude=src/test/regress/results '
                           f'--exclude=src/test/regress/log '
                           f'--exclude=src/test/isolation/results '
                           f'--exclude=src/test/isolation/output_iso '
                           f'-cf - . | tar -C {test_srcdir} -xf -')
        self.node.putfile('scripts/run_postgres_tests.sh', self.testsdir)
        self.node.exec(f'mv {self.testsdir.joinpath("run_postgres_tests.sh")} '
                       f'{self.testsdir.joinpath("run.sh")}')
        self.node.exec(f'chmod +x {self.testsdir.joinpath("run.sh")}')
        self.copy_test_tools((
            'perl',
            'prove',
        ))
        test_perldir = self.testsdir.joinpath('lib/copied/perl')
        with self.nixenv():
            copy_perl(self.node, test_perldir)
        super().copy_deps(self.testsdir)
        self.copy_patchelf(self.testsdir)
        test_envs = [
            'PERL5LIB=$TOPDIR/lib/copied/perl',
        ]
        wrap_envs(self.node,
                  self.testsdir,
                  self.test_env_bins,
                  test_envs)
        # ECPG installcheck 会按 mtime 判断是否重生成测试程序；依赖包装后刷新产物时间戳，避免目标机重新调用 gcc。
        ecpg_testdir = self.testsdir.joinpath('src/src/interfaces/ecpg/test')
        self.node.exec(f'find {ecpg_testdir} -mindepth 2 -maxdepth 2 -name Makefile '
                       f"-exec sed -i -E 's/^all:.*$/all:/' {{}} +")
        self.node.exec(f'find {ecpg_testdir} -name Makefile '
                       f"-exec sed -i -E 's/[A-Za-z0-9_]+\\.c//g' {{}} +")
        self.node.exec(f'find {ecpg_testdir} -type f -exec touch {{}} +')
        self.node.exec(f'find {ecpg_testdir} -type f -perm -111 -exec touch {{}} +')
        self.node.exec(f'find {self.testsdir} -type f -name "*.c" -delete')

    @property
    def test_pkgname(self) -> str:
        """
        测试包名。
        """
        return f'postgres-tests-{self.version}-{self.options.system}-glibc{self.glibc_version}.tar.gz'

    def copy_deps(self) -> None:
        """
        拷贝依赖，并补充 PL/Perl 和 PL/Python 运行时需要的库。
        """
        elfdir = PurePosixPath(self.instdir)
        pythondir = None
        perldir = None
        tcldir = None
        with self.nixenv():
            if '--with-perl' in self.configure_options:
                perldir = elfdir.joinpath('lib/copied/perl')
                copy_perl(self.node, perldir)
            if '--with-python' in self.configure_options:
                pythondir = elfdir.joinpath('lib/copied/python')
                copy_python(self.node, pythondir)
            if '--with-tcl' in self.configure_options:
                tcldir = elfdir.joinpath('lib/copied/tcl')
                copy_tcl(self.node, tcldir)

        super().copy_deps(elfdir,
                          copylocales=True)
        envs = [
            'LOCALE_ARCHIVE=$TOPDIR/lib/copied/locale-archive',
        ]
        if pythondir is not None:
            envs.extend((
                'PYTHONHOME=$TOPDIR/lib/copied/python',
                'PYTHONPATH=$TOPDIR/lib/copied/python:$TOPDIR/lib/copied/python/lib-dynload',
            ))
        if perldir is not None:
            envs.append('PERL5LIB=$TOPDIR/lib/copied/perl')
        if tcldir is not None:
            envs.extend((
                'TCL_LIBRARY=$TOPDIR/lib/copied/tcl',
                'TCLLIBPATH=$TOPDIR/lib/copied/tcl',
            ))
        wrap_envs(self.node,
                  elfdir,
                  self.runtime_env_bins,
                  envs)

    @property
    def runtime_env_bins(self) -> tuple[str, ...]:
        """
        数据库运行时需要环境变量注入的程序。
        """
        return (
            'bin/postgres',
            'bin/pg_ctl',
            'bin/initdb',
            'bin/pg_upgrade',
            'bin/pg_basebackup',
            'bin/pg_combinebackup',
            'bin/pg_verifybackup',
            'bin/pg_receivewal',
            'bin/pg_recvlogical',
            'bin/pg_rewind',
            'bin/pg_createsubscriber',
            'bin/pg_amcheck',
            'bin/pg_checksums',
            'bin/pg_controldata',
            'bin/pg_resetwal',
            'bin/pg_waldump',
            'bin/pg_walsummary',
        )

    @property
    def test_env_bins(self) -> tuple[str, ...]:
        """
        测试运行时需要环境变量注入的程序。
        """
        return (
            'tools/bin/perl',
        )

    def teardown(self) -> None:
        """
        后置步骤。
        """
        super().teardown()

    @cached_property
    def version(self) -> str:
        """
        程序版本号。
        """
        with self.node.dir(self.instdir):
            with self.nixenv():
                return self.node.exec(f'./bin/postgres --version').getfield('postgres', 3)
