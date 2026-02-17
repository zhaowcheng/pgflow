import textwrap

from typing import Optional, Generator
from contextlib import contextmanager
from functools import cached_property
from pathlib import PurePosixPath

from xflow.framework.pipeline import Pipeline
from .scripts import copy_deps, set_rpath, set_interp


class pack(Pipeline):
    """
    打包基类。
    """
    class Options(Pipeline.Options):
        """
        流水线参数表。
        """
        repo_url: str = Pipeline.Option(desc='Repository URL.')
        revision: str = Pipeline.Option(desc='Branch, tag, or commit.')
        system: str = Pipeline.Option(desc='The target system to build.',
                                      choices=('x86_64-linux', 
                                               'aarch64-linux', 
                                               'loongarch64-linux', 
                                               'mips64el-linux'))
        progname: str = Pipeline.Option(desc='Program name.')
        nix_flakes_dir: str = Pipeline.Option(desc='Nix flakes directory.',
                                              default='~/flakes')
        nix_env_name: str = Pipeline.Option(desc='Nix shell environment name.')

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
    def version(self) -> str:
        """
        程序版本号。
        """
        raise NotImplementedError
    
    @contextmanager
    def nixenv(self) -> Generator[None, None, None]:
        """
        进入 nix_* 等参数指定的 nix shell 环境。
        """
        with self.node.nixenv(self.options.nix_flakes_dir,
                              self.options.system,
                              name=self.options.nix_env_name):
            yield

    def archive(
        self, 
        directory: str | PurePosixPath,
        pkgstem: str
    ) -> None:
        """
        压缩节点上的目录 `directory` 并下载。

        :param directory: 节点上要归档的目录。
        :param pkgstem: 压缩后的文件名（不含后缀）。
        """
        pkgname = f'{pkgstem}.tar.gz'
        self.node.exec(f'tar czvf {pkgname} -C {directory} .')
        pkgpath = self.node.cwd.joinpath(pkgname)
        self.node.getfile(pkgpath, self.cwd)

    @property
    def pkgstem(self) -> str:
        """
        包名（不包含后缀）。
        """
        return f'{self.options.progname}-{self.version}-{self.options.system}'

class pack_c(pack):
    """
    C/C++ 程序打包基类。
    """
    class Options(pack.Options):
        """
        流水线参数表。
        """
        configure_options: Optional[str] = Pipeline.Option(desc='Configure options.')

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

    def handle_deps(
        self,
        instdir: str | PurePosixPath
    ) -> None:
        """
        处理依赖。

        :param instdir: 被处理的安装目录。
        """
        def _copy_deps(instdir: PurePosixPath):
            with self.nixenv():
                libdir = instdir.joinpath('lib')
                bindir = instdir.joinpath('bin')
                destdir = libdir.joinpath('sys')
                self.node.exec(f'mkdir -p {destdir}')
                copy_deps(self.node, instdir, destdir, excludedirs=f'{libdir}')
                set_rpath(self.node, instdir, f'{libdir}:{destdir}')
                libc_path = destdir.joinpath('libc.so.6')
                interp_path = self.node.exec(f'patchelf --print-interpreter {libc_path}')
                interp_name = interp_path.split('/')[-1]
                self.node.exec(f'cp {interp_path} {destdir}')
                set_interp(self.node, bindir, f'./lib/sys/{interp_name}')
        # 拷贝被打包程序的依赖
        instdir = PurePosixPath(instdir)
        _copy_deps(instdir)
        # 创建配置脚本和说明
        scripts_dir = instdir.joinpath('scripts')
        patchelf_parent = scripts_dir.joinpath('patchelf')
        patchelf_bindir = patchelf_parent.joinpath('bin')
        patchelf_libdir = patchelf_parent.joinpath('bin')
        with self.nixenv():
            patchelf_bin = self.node.exec('which patchelf')
        self.node.exec(f'mkdir -p {patchelf_bindir}')
        self.node.exec(f'mkdir -p {patchelf_libdir}')
        self.node.exec(f'cp -v {patchelf_bin} {patchelf_bindir}')
        _copy_deps(patchelf_parent)
        self.node.putfile('scripts/setup_c.sh', scripts_dir)
        self.node.exec(f'cd {scripts_dir} && mv setup_c.sh setup.sh')
        self.node.exec(f'chmod +x {scripts_dir}/*')
        self.node.write(textwrap.dedent("""
        1、本安装包自带了所有依赖（包括 glibc），并且为所有 ELF 文件设置了 RPATH 
           自动查找自带的依赖，所以无需配置 LD_LIBRARY_PATH 即可使用。
        2、打包时已把所有 bin 目录下的程序的 interpreter 设置为指向 lib/sys
           目录中 interpreter 的相对路径，所以一开始只能在解压后的目录下执行程序才
           可成功（如 ./bin/myprog），解压完成后请执行 scripts/setup.sh 脚本
           进行初始配置，配置完成后会把 interpreter 修改为绝对路径，如果安装路径
           发生变更，需重新执行 scripts/setup.sh 脚本。
        """), f'{instdir.joinpath("README")}')

class pack_pgext(pack_c):
    """
    postgres 扩展打包基类。
    """
    class Options(pack_c.Options):
        """
        流水线参数表。
        """
        pg_pkg_url: str = Pipeline.Option(desc='The postgres package url.')

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

    def download_postgres(
        self,
        directory: str | PurePosixPath
    ) -> None:
        """
        下载 postgres 包。

        :param directory: 下载目录。
        """
        self.node.exec(f'mkdir -p {directory}')
        with self.node.dir(directory):
            pkgname = self.options.pg_pkg_url.split('/')[-1]
            self.node.exec(f'wget {self.options.pg_pkg_url}')
            self.node.exec(f'tar xvf {pkgname} && rm {pkgname}')
            self.node.exec('./scripts/setup.sh')
    
    def handle_deps(
        self,
        instdir: str | PurePosixPath,
        pgdir:  str | PurePosixPath
    ) -> None:
        """
        处理依赖。

        :param instdir: 被处理的安装目录。
        :param pgdir: postgres 安装目录。
        """
        instdir = PurePosixPath(instdir)
        libdir = instdir.joinpath('lib')
        bindir = instdir.joinpath('bin')
        syslib = libdir.joinpath('sys')
        pgdir = PurePosixPath(pgdir)
        pglib = pgdir.joinpath('lib')
        pgsys = pglib.joinpath('sys')
        if self.node.exists(libdir):
            self.node.exec(f'mkdir -p {syslib}')
            with self.nixenv():
                copy_deps(self.node, instdir, syslib, 
                          excludedirs=f'{libdir}:{pglib}:{pgsys}')
                set_rpath(self.node, instdir, f'{libdir}:{syslib}')
        if self.node.exists(bindir):
            with self.nixenv():
                libc_path = pgsys.joinpath('libc.so.6')
                interp_path = self.node.exec(f'patchelf --print-interpreter {libc_path}')
                interp_name = interp_path.split('/')[-1]
                set_interp(self.node, bindir, f'./lib/sys/{interp_name}')
        self.node.write(textwrap.dedent("""
        本扩展安装包是专为指定数据库安装包而打的，直接解压到数据库安装目录下，
        然后执行安装目录下的 scripts/setup.sh 脚本，即算安装完成。
        """), f'{instdir.joinpath("README-EXT")}')
