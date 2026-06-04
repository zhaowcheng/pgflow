from functools import cached_property
from pathlib import PurePosixPath
from typing_extensions import Self

from xflow.framework.pipeline import Pipeline
from .common.pack import pack_c
from .common.scripts import copy_python, wrap_runtime

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
        
        @model_validator(mode='after')
        def default_configure_options(self) -> Self:
            """
            默认 configure 参数。
            """
            if not self.configure_options:
                self.configure_options = '--enable-nls ' \
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
                                         '--with-selinux '
                if self.system not in ['mips64el-linux']:
                    self.configure_options += '--with-systemd ' \
                                              '--with-libcurl '
                if self.system not in ['loongarch64-linux', 'mips64el-linux']:
                    self.configure_options += '--with-llvm '
            return self

    def setup(self) -> None:
        """
        前置步骤。
        """
        self.options: __class__.Options  # 保留用于自动提示
        super().setup()

        self.configure_options = (self.options.configure_options or '') + f' --prefix={self.instdir}'

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
        
    def stage2(self) -> None:
        """
        编译。
        """
        with self.node.dir(self.codedir):
            with self.nixenv():
                self.node.exec(f'./configure {self.configure_options}')
                self.node.exec('make world -j`nproc`')
                self.node.exec('make install-world')

    def stage3(self) -> None:
        """
        打包。
        """
        self.copy_deps(self.instdir, copylocales=True)
        self.copy_instscript(self.packdir)
        self.archive(self.packdir, self.pkgname)

    def copy_deps(
        self,
        elfdir: str | PurePosixPath,
        excludedirs: str | None = None,
        copyinterp: bool = True,
        checkdeps: bool = True,
        copylocales: bool = False
    ) -> None:
        """
        拷贝依赖，并补充 PL/Python 运行时需要的 Python 标准库。
        """
        elfdir = PurePosixPath(elfdir)
        pythondir = None
        if elfdir == PurePosixPath(self.instdir) and '--with-python' in self.configure_options:
            pythondir = elfdir.joinpath('lib/copied/python')
            with self.nixenv():
                copy_python(self.node, pythondir)

        super().copy_deps(elfdir,
                          excludedirs=excludedirs,
                          copyinterp=copyinterp,
                          checkdeps=checkdeps,
                          copylocales=copylocales)

        if pythondir is not None and copylocales:
            wrap_runtime(self.node,
                         elfdir,
                         PurePosixPath('lib/copied'),
                         pythondir=pythondir)

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
