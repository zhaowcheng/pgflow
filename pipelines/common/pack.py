from typing import Optional, Generator
from contextlib import contextmanager
from functools import cached_property
from pathlib import PurePosixPath

from xflow.framework.pipeline import Pipeline
from .scripts import copy_deps, check_deps, set_rpath, set_interp, wrap_locale


class pack(Pipeline):
    """
    打包基类。
    """
    class Options(Pipeline.Options):
        """
        流水线参数表。
        """
        repourl: str = Pipeline.Option(desc='Repository URL.')
        revision: Optional[str] = Pipeline.Option(desc='Branch, tag, or commit.')
        system: str = Pipeline.Option(desc='The target system to build.',
                                      choices=('x86_64-linux',
                                               'aarch64-linux',
                                               'loongarch64-linux',
                                               'mips64el-linux'))
        progname: str = Pipeline.Option(desc='Program name.')
        nix_flakes_dir: str = Pipeline.Option(desc='Nix flakes directory.',
                                              default='~/flakes')
        nix_env_name: str = Pipeline.Option(desc='Nix shell environment name.')

        @property
        def arch(self) -> str:
            """
            CPU 架构。
            """
            return self.system.split('-')[0]

    def setup(self) -> None:
        """
        前置步骤。
        """
        self.options: __class__.Options  # 保留用于自动提示
        super().setup()

        # 标准目录。
        self.codedir = self.node.cwd.joinpath('code')
        self.packdir = self.node.cwd.joinpath('package')
        self.instdir = self.packdir.joinpath('content')
        self.node.exec(f'mkdir -p {self.instdir}')

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
        raise NotImplementedError

    @contextmanager
    def nixenv(self, options: Optional[str] = None) -> Generator[None, None, None]:
        """
        使用 nix develop 进入 nix_* 等参数指定的 nix shell 环境。

        :param options: nix develop 命令选项。
        """
        with self.node.nixenv(self.options.nix_flakes_dir,
                              system=self.options.system,
                              name=self.options.nix_env_name,
                              options=options):
            yield

    def archive(
        self,
        directory: str | PurePosixPath,
        pkgname: Optional[str] = None
    ) -> None:
        """
        压缩节点上的目录 `directory` 并下载。

        :param directory: 节点上要归档的目录。
        :param pkgname: 压缩后的文件名。
        """
        pkgname = pkgname or self.pkgname
        self.node.exec(f'chmod -R +w {directory}')
        self.node.exec(f'tar czf {pkgname} -C {directory} .')
        pkgpath = self.node.cwd.joinpath(pkgname)
        self.node.getfile(pkgpath, self.cwd)

    @property
    def pkgstem(self) -> str:
        """
        包名（不包含后缀）。
        """
        return f'{self.options.progname}-{self.version}-{self.options.system}'

    @property
    def pkgname(self) -> str:
        """
        包名。
        """
        return f'{self.pkgstem}.tar.gz'

    def copy_instscript(
        self,
        destdir: str | PurePosixPath,
        script: str = 'install.sh'
    ) -> None:
        """
        准备安装脚本。

        :param destdir: 目标目录。
        :param script: 安装脚本名。
        """
        self.node.putfile(f'scripts/{script}', destdir)
        with self.node.dir(destdir):
            if script != 'install.sh':
                self.node.exec(f'mv {script} install.sh')
            self.node.exec('chmod +x install.sh')


class pack_c(pack):
    """
    C/C++ 程序打包基类。
    """
    class Options(pack.Options):
        """
        流水线参数表。
        """
        configure_options: Optional[str] = Pipeline.Option(desc='Configure options.',
                                                           default='')

    def setup(self) -> None:
        """
        前置步骤。
        """
        self.options: __class__.Options  # 保留用于自动提示
        super().setup()

    def teardown(self) -> None:
        """
        后置步骤。
        """
        super().teardown()

    @cached_property
    def glibc_version(self) -> str:
        """
        编译环境的 glibc 版本号，如 `2.40`。
        """
        with self.nixenv():
            return self.node.exec('getconf GNU_LIBC_VERSION').getfield('glibc', 2)

    @property
    def pkgstem(self) -> str:
        """
        包名（不包含后缀）。
        """
        return f'{super().pkgstem}-glibc{self.glibc_version}'

    def copy_deps(
        self,
        elfdir: str | PurePosixPath,
        excludedirs: Optional[str] = None,
        copyinterp: bool = True,
        checkdeps: bool = True,
        copylocales: bool = False
    ) -> None:
        """
        拷贝依赖。

        :param elfdir: 需要拷贝其依赖的目录。
        :param excludedirs: 拷贝依赖时需要排除的目录。
        :param copyinterp: 是否拷贝动态库解释器。
        :param checkdeps: 拷贝完成后是否检查依赖。
        :param copylocales: 是否拷贝 locales 数据。
        """
        elfdir = PurePosixPath(elfdir)
        libdir = elfdir.joinpath('lib')
        destdir = libdir.joinpath('copied')
        if excludedirs:
            full_excludedirs = f'{libdir}:{excludedirs}'
        else:
            full_excludedirs = f'{libdir}'
        self.node.exec(f'mkdir -p {destdir}')
        with self.nixenv():
            copy_deps(self.node, elfdir, destdir, excludedirs=full_excludedirs)
            set_rpath(self.node, elfdir, f'{libdir}:{destdir}')
        if checkdeps:
            check_deps(self.node, elfdir)
        if copyinterp:
            with self.nixenv():
                bash_path = self.node.exec('which bash')
                interp_path = self.node.exec(f'patchelf --print-interpreter {bash_path}')
                interp_name = interp_path.split('/')[-1]
                self.node.exec(f'cp {interp_path} {destdir}')
                set_interp(self.node, elfdir, f'./lib/copied/{interp_name}')
        if copylocales:
            locales_savedir = elfdir.joinpath('etc')
            self.node.exec(f'mkdir -p {locales_savedir}')
            with self.nixenv():
                self.node.exec(f"sh -c 'cp -v $LOCALE_ARCHIVE {locales_savedir}'")
            wrap_locale(self.node, elfdir)

    def copy_patchelf(self, destdir: str | PurePosixPath) -> None:
        """
        拷贝 patchelf 及其依赖。

        :param destdir: 拷贝的目标目录。
        """
        destdir = PurePosixPath(destdir)
        parent = destdir.joinpath('patchelf')
        bindir = parent.joinpath('bin')
        libdir = parent.joinpath('lib')
        with self.nixenv():
            patchelf = self.node.exec('which patchelf')
            file = self.node.exec('which file')
            filedir = file.replace('/bin/file', '')
            filesharedir = f'{filedir}/share'
        self.node.exec(f'mkdir -p {bindir}')
        self.node.exec(f'mkdir -p {libdir}')
        self.node.exec(f'cp -v {patchelf} {bindir}')
        self.node.exec(f'cp -v {file} {bindir}')
        self.node.exec(f'cp -rv {filesharedir} {parent}')
        self.copy_deps(parent)

    def copy_instscript(
        self,
        destdir: str | PurePosixPath,
        script: str = 'install.sh'
    ) -> None:
        """
        准备安装脚本。

        :param destdir: 目标目录。
        :param script: 安装脚本名。
        """
        super().copy_instscript(destdir, script=script)
        self.copy_patchelf(destdir)

    def handle_deps(
        self,
        instdir: str | PurePosixPath
    ) -> None:
        """
        兼容旧流水线入口。新流水线优先直接调用 copy_deps。
        """
        self.copy_deps(instdir)


class pack_pgceco(pack_c):
    """
    编译时需要 postgres 包的 C/C++ 生态（扩展、工具）打包基类。
    """
    class Options(pack_c.Options):
        """
        流水线参数表。
        """
        nix_env_name: str = Pipeline.Option(desc='Nix shell environment name.',
                                            default='postgres')
        pg_pkg_url: str = Pipeline.Option(desc='The postgres package url.')

    def setup(self) -> None:
        """
        前置步骤。
        """
        self.options: __class__.Options  # 保留用于自动提示
        super().setup()

        self.pgdir = self.node.cwd.joinpath('postgres')

    def teardown(self) -> None:
        """
        后置步骤。
        """
        super().teardown()

    @contextmanager
    def nixenv(self, options: Optional[str] = None) -> Generator[None, None, None]:
        """
        使用 nix develop 进入 nix_* 等参数指定的 nix shell 环境。
        """
        options = (options or '') + f' -s PATH {self.pgdir}/bin:$PATH -s LD_LIBRARY_PATH {self.pgdir}/lib'
        with super().nixenv(options=options):
            yield

    def install_postgres(
        self,
        directory: Optional[str | PurePosixPath] = None
    ) -> None:
        """
        下载并安装 postgres 包。

        :param directory: 安装目录。
        """
        directory = PurePosixPath(directory or self.pgdir)
        savedir = self.node.cwd.joinpath('postgres_pkg')
        self.node.exec(f'mkdir -p {savedir} {directory}')
        with self.node.dir(savedir):
            pkgname = self.options.pg_pkg_url.split('/')[-1]
            self.node.exec(f'wget {self.options.pg_pkg_url}')
            self.node.exec(f'tar xf {pkgname}')
            self.node.exec(f'rm -f {pkgname}')
            with self.nixenv():
                self.node.exec(f'./install.sh {directory}')


class pack_python(pack_c):
    """
    Python 程序打包基类。
    """
    class Options(pack_c.Options):
        """
        流水线参数表。
        """
        nix_env_name: str = Pipeline.Option(desc='Nix shell environment name.',
                                            default='python')

    def setup(self) -> None:
        """
        前置步骤。
        """
        self.options: __class__.Options  # 保留用于自动提示
        super().setup()

    def teardown(self) -> None:
        """
        后置步骤。
        """
        super().teardown()
