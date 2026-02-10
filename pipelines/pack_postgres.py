from functools import cached_property
from typing_extensions import Self

from xflow.framework.pipeline import Pipeline
from .common.pack import pack_c

from pydantic import model_validator


class pack_postgres(pack_c):
    """
    postgres 打包流程。
    """
    PROGNAME = 'postgres'    

    class Options(pack_c.Options):
        """
        流水线参数表。
        """
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

    def stage1(self) -> None:
        """
        拉取代码。
        """
        super().stage1()
        
    def stage2(self) -> None:
        """
        编译。
        """
        with self.node.dir('code'):
            with self.nixenv():
                self.node.exec(f'./configure {self.configure_options}')
                self.node.exec('make -j`nproc` world')
                self.node.exec('make install-world')

    def stage3(self) -> None:
        """
        打包。
        """
        self.handle_deps()
        self.archive()

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
    
