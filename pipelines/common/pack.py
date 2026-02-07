import textwrap

from typing import Optional, Generator
from contextlib import contextmanager
from functools import cached_property
from pathlib import PurePosixPath

from xflow.framework.pipeline import Pipeline
from .scripts import copy_deps, set_rpath, set_interp


class pack(Pipeline):
    """
    打包流水线基类。
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
        nix_flakes_dir: str = Pipeline.Option(desc='Nix flakes directory.',
                                              default='~/flakes')
        nix_env_name: str = Pipeline.Option(desc='Nix shell environment name.')

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
        self.node.git(self.options.repo_url,
                      self.options.revision,
                      directory='code')
        
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
        progname: str, 
        ardir: str | PurePosixPath,
        suffix: str = ''
    ) -> None:
        """
        归档。

        :param progname: 程序名。
        :param ardir: 要归档的目录。
        :param suffix: 包名后缀（名称和 `.tar.gz` 之间）
        """
        tarname = f'{progname}-{self.version}-{self.options.system}{suffix}.tar.gz'
        self.node.exec(f'tar czvf {tarname} -C {ardir} .')
        tarpath = self.node.cwd.joinpath(tarname)
        self.node.getfile(tarpath, self.cwd)


class pack_c(pack):
    """
    C/C++ 程序打包流程基类。
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

        # 参数准备
        self.instdir = self.node.cwd.joinpath('install')
        self.configure_options = (self.options.configure_options or '') + f' --prefix={self.instdir}'

    def teardown(self) -> None:
        """
        后置步骤。
        """
        super().teardown()

    def archive(
        self, 
        progname: str, 
        ardir: str | PurePosixPath
    ) -> None:
        """
        归档。

        :param progname: 程序名。
        :param ardir: 要归档的目录。
        """
        with self.nixenv():
            suffix = self.node.exec('getconf GNU_LIBC_VERSION').replace(' ', '')
        super().archive(progname, ardir, suffix=f'-{suffix}')

    def handle_deps(self) -> None:
        """
        处理依赖。
        """
        def _copy_deps(instdir: PurePosixPath):
            with self.nixenv():
                libdir = instdir.joinpath('lib')
                bindir = instdir.joinpath('bin')
                copieddir = libdir.joinpath('copied')
                self.node.exec(f'mkdir -p {copieddir}')
                copy_deps(self.node, instdir, copieddir)
                set_rpath(self.node, instdir, f'{libdir}:{copieddir}')
                libc_path = copieddir.joinpath("libc.so.6")
                interp_path = self.node.exec(f'patchelf --print-interpreter {libc_path}')
                interp_name = interp_path.split('/')[-1]
                self.node.exec(f'cp {interp_path} {copieddir}')
                set_interp(self.node, bindir, f'./lib/copied/{interp_name}')
        # 拷贝被打包程序的依赖
        _copy_deps(self.instdir)
        # 创建配置脚本和说明
        scripts_dir = self.instdir.joinpath('scripts')
        patchelf_parent = scripts_dir.joinpath('patchelf')
        patchelf_bindir = patchelf_parent.joinpath('bin')
        patchelf_libdir = patchelf_parent.joinpath('bin')
        with self.nixenv():
            patchelf_bin = self.node.exec('which patchelf')
        self.node.exec(f'mkdir -p {patchelf_bindir}')
        self.node.exec(f'mkdir -p {patchelf_libdir}')
        self.node.exec(f'cp -v {patchelf_bin} {patchelf_bindir}')
        _copy_deps(patchelf_parent)
        self.node.putfile('scripts/setup.sh', scripts_dir)
        self.node.exec(f'chmod +x {scripts_dir}/*')
        self.node.write(textwrap.dedent("""
        1、本安装包自带了所有依赖（包括 glibc），并且为所有 ELF 文件设置了 RPATH 
           自动查找自带的依赖，所以无需配置 LD_LIBRARY_PATH 即可使用。
        2、打包时已把所有 bin 目录下的程序的 interpreter 设置为指向 lib/copied
           目录中 interpreter 的相对路径，所以一开始只能在解压后的目录下执行程序才
           可成功（如 ./bin/myprog），解压完成后请执行 scripts/setup.sh 脚本
           进行初始配置，配置完成后会把 interpreter 修改为绝对路径，如果安装路径
           发生变更，需重新执行 scripts/setup.sh 脚本。
        """), f'{self.instdir.joinpath("README")}')
