from functools import cached_property
from typing_extensions import Self

from xflow.framework.pipeline import Pipeline
from .common.pack import pack_pgceco

from pydantic import model_validator


class pack_pgpool(pack_pgceco):
    """
    pgpool 打包流程。
    """
    class Options(pack_pgceco.Options):
        """
        流水线参数表。
        """
        progname: str = Pipeline.Option(desc='Program name.',
                                        default='pgpool')
        
        @model_validator(mode='after')
        def default_configure_options(self) -> Self:
            """
            默认 configure 参数。
            """
            if not self.configure_options:
                self.configure_options = '--with-openssl ' \
                                         '--with-pam ' \
                                         '--with-ldap '
            return self

    def setup(self) -> None:
        """
        前置步骤。
        """
        self.options: __class__.Options  # 保留用于自动提示
        super().setup()

        # 参数准备
        self.instdir = self.node.cwd.joinpath('install')
        self.pgdir = self.node.cwd.joinpath('postgres')
        self.configure_options = (self.options.configure_options or '') + f' --prefix={self.instdir}'

    def stage1(self) -> None:
        """
        拉取代码。
        """
        self.node.git(self.options.repo_url,
                      self.options.revision,
                      directory='code')
        self.download_postgres(self.pgdir)
        
    def stage2(self) -> None:
        """
        编译。
        """
        with self.node.dir('code'):
            with self.nixenv(options=f'-s PATH {self.pgdir}/bin:$PATH'):
                self.node.exec('autoreconf -fi')
                self.node.exec(f'./configure {self.configure_options}')
                self.node.exec('make -j`nproc`')
                self.node.exec('make install')

    def stage3(self) -> None:
        """
        打包。
        """
        self.handle_deps(self.instdir)
        self.archive(self.instdir, self.pkgstem)

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
                return self.node.exec(f'./bin/pgpool --version').getfield('pgpool', 3)
