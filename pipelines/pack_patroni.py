from typing import Optional, Generator
from functools import cached_property
from contextlib import contextmanager

from xflow.framework.pipeline import Pipeline

from .common.pack import pack, pack_python, pack_pgceco


class pack_patroni(pack_python, pack_pgceco):
    """
    patroni 打包流程。
    """
    class Options(pack_python.Options, pack_pgceco.Options):
        """
        流水线参数表。
        """
        repourl: str = Pipeline.Option(desc='Repository URL.',
                                       default='https://github.com/patroni/patroni.git')
        progname: str = Pipeline.Option(desc='Program name.',
                                        default='patroni')

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
        self.node.git(self.options.repourl,
                      self.options.revision,
                      directory=self.codedir)
        self.install_postgres(self.pgdir)

    def stage2(self) -> None:
        """
        编译。
        """
        with self.node.dir(self.codedir):
            with self.nixenv():
                self.node.exec('pip install psycopg2 nuitka')
                self.node.exec('pip install -r $( [ -f requirements.txt ] && echo "requirements.txt" || echo "install_deps.txt" )')
                self.node.exec('python -m nuitka '
                               '--mode=standalone '
                               '--output-filename=patroni '
                               '--include-module=patroni.dcs.consul '
                               '--include-module=patroni.dcs.etcd '
                               '--include-module=patroni.dcs.etcd3 '
                               '--include-module=patroni.dcs.exhibitor '
                               '--include-module=patroni.dcs.kubernetes '
                               '--include-module=patroni.dcs.raft '
                               '--include-module=patroni.dcs.zookeeper '
                               '--include-module=http.server '
                               '--include-data-dir=patroni/postgresql/available_parameters/=patroni/postgresql/available_parameters/ '
                               'patroni.py')
                self.node.exec('python -m nuitka '
                               '--mode=standalone '
                               '--output-filename=patronictl '
                               'patronictl.py')
            self.node.exec(f'mkdir -p {self.instdir}/{{bin,lib}}')
            self.node.exec(f'cp -r patroni.dist/* {self.instdir}/lib/')
            self.node.exec(f'cp -r patronictl.dist/* {self.instdir}/lib/')
        with self.node.dir(self.instdir):
            self.node.exec('cd bin && ln -s ../lib/patroni . && ln -s ../lib/patronictl .')

    def stage3(self) -> None:
        """
        打包。
        """
        self.copy_deps(self.instdir)
        self.copy_instscript(self.packdir)
        self.archive(self.packdir, self.pkgname)

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
        with pack.nixenv(self, options=options):
            yield

    @cached_property
    def version(self) -> str:
        """
        程序版本号。
        """
        with self.node.dir(self.codedir):
            line = self.node.exec("grep '^__version__' patroni/version.py")
            return line.split('=')[1].strip().strip("'\"")
