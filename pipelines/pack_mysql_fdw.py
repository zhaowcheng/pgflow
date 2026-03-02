from functools import cached_property
from textwrap import dedent

from xflow.framework.pipeline import Pipeline

from .common.pack import pack_pgext


class pack_mysql_fdw(pack_pgext):
    """
    mysql_fdw 打包流程。
    """
    class Options(pack_pgext.Options):
        """
        流水线参数表。
        """
        progname: str = Pipeline.Option(desc='Program name.',
                                        default='mysql_fdw')
        
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
            with self.nixenv(options=f'-s PATH {self.pgdir}/bin:$PATH'):
                self.node.exec('make USE_PGXS=1')
                self.node.exec(f'make install USE_PGXS=1 DESTDIR={self.destdir}')

    def stage3(self) -> None:
        """
        打包。
        """
        self.node.exec(f'mkdir -p {self.instdir}/lib')
        copy_libmysql_script = self.node.cwd.joinpath('copy_libmysql.sh')
        self.node.write(dedent(f"""\
        #!/bin/bash -e
        cp $MYSQL_HOME/lib/mysql/libmysqlclient.so {self.instdir}/lib/
        """), copy_libmysql_script)
        self.node.exec(f'chmod +x {copy_libmysql_script}')
        with self.nixenv():
            self.node.exec(copy_libmysql_script)
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
            return self.node.exec('cat mysql_fdw.c | grep "version is"').split()[4]
