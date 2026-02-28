from functools import cached_property

from xflow.framework.pipeline import Pipeline

from .common.pack import pack_pgext


class pack_postgis(pack_pgext):
    """
    postgis 打包流程。
    """
    class Options(pack_pgext.Options):
        """
        流水线参数表。
        """
        progname: str = Pipeline.Option(desc='Program name.',
                                        default='postgis')
        nix_env_name: str = Pipeline.Option(desc='Nix shell environment name.',
                                            default='postgres')
        
        
    def setup(self) -> None:
        """
        前置步骤。
        """
        self.options: __class__.Options  # 保留用于自动提示
        super().setup()

        # 参数准备
        self.destdir = self.node.cwd.joinpath('destdir')
        self.pgdir = self.node.cwd.joinpath('postgres')
        self.instdir = self.destdir.joinpath(self.pgdir.relative_to('/'))

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
            with self.nixenv(options=f'-s PATH {self.pgdir}/bin'):
                configure_options = self.options.configure_options or ''
                if self.options.system in ['loongarch64-linux', 'mips64el-linux']:
                    configure_options += ' --without-raster'
                self.node.exec('./autogen.sh')
                self.node.exec(f'./configure {configure_options}')
                self.node.exec('make -j`nproc`')
                self.node.exec(f'make install DESTDIR={self.destdir}')
                self.node.exec(f'mv {self.destdir}/usr/local/bin {self.instdir}')

    def stage3(self) -> None:
        """
        打包。
        """
        self.handle_deps(self.instdir, self.pgdir)
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
        with self.node.dir('code'):
            result = self.node.exec('cat Version.config')
            major = result.getfield('POSTGIS_MAJOR_VERSION=', 2, sep='=')
            minor = result.getfield('POSTGIS_MINOR_VERSION=', 2, sep='=')
            micro = result.getfield('POSTGIS_MICRO_VERSION=', 2, sep='=')
            return f'{major}.{minor}.{micro}'
