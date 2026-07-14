"""
通用 PostgreSQL 扩展打包流程。

已支持扩展：
- pgvector
- pgroonga
- postgis
- zhparser
- mysql_fdw
- oracle_fdw

以后新增支持的扩展时，请同步把扩展名添加到上面的清单。
"""

from functools import cached_property
from textwrap import dedent
from typing import Optional

from pydantic import model_validator
from typing_extensions import Self
from xflow.framework.pipeline import Pipeline

from .common.pack import pack_pgceco


EXT_REPOURLS = {
    'pgvector': 'https://github.com/pgvector/pgvector.git',
    'pgroonga': 'https://github.com/pgroonga/pgroonga.git',
    'postgis': 'https://github.com/postgis/postgis.git',
    'zhparser': 'https://github.com/amutu/zhparser.git',
    'mysql_fdw': 'https://github.com/EnterpriseDB/mysql_fdw.git',
    'oracle_fdw': 'https://github.com/laurenz/oracle_fdw.git',
}


class pack_pgext(pack_pgceco):
    """
    通用 PostgreSQL 扩展打包流程。
    """
    class Options(pack_pgceco.Options):
        """
        流水线参数表。
        """
        progname: str = Pipeline.Option(desc='Program name.',
                                        choices=tuple(EXT_REPOURLS.keys()),
                                        default='pgvector')
        repourl: Optional[str] = Pipeline.Option(desc='Repository URL.')

        @model_validator(mode='after')
        def default_repourl(self) -> Self:
            """
            根据扩展名设置默认仓库地址。
            """
            if not self.repourl:
                self.repourl = EXT_REPOURLS[self.progname]
            return self

    def setup(self) -> None:
        """
        前置步骤。
        """
        self.options: __class__.Options  # 保留用于自动提示
        super().setup()

        self.destdir = self.node.cwd.joinpath('destdir')
        self.real_instdir = self.destdir.joinpath(self.pgdir.relative_to('/'))

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
                # configure
                if self.options.progname == 'postgis':
                    configure_options = self.options.configure_options or ''
                    if self.options.system in ['loongarch64-linux']:
                        configure_options += ' --without-raster'
                    self.node.exec('./autogen.sh')
                    self.node.exec(f'./configure {configure_options}')
                # make
                if self.options.progname == 'pgroonga':
                    self.node.exec('make -j `nproc` HAVE_MSGPACK=1')
                else:
                    self.node.exec('make -j `nproc`')
                # make install
                self.node.exec(f'make install USE_PGXS=1 DESTDIR={self.destdir}')
        self.node.exec(f'cp -r {self.real_instdir}/* {self.instdir}')
        if self.options.progname == 'postgis':
            self.node.exec(f'if [[ -d {self.destdir}/usr/local/bin ]]; then mv {self.destdir}/usr/local/bin {self.instdir}; fi')

    def stage3(self) -> None:
        """
        打包。
        """
        if self.options.progname == 'mysql_fdw':
            self.node.exec(f'mkdir -p {self.instdir}/lib')
            copy_libmysql_script = self.node.cwd.joinpath('copy_libmysql.sh')
            self.node.write(dedent(f"""\
            #!/bin/bash -e
            cp $MYSQL_HOME/lib/mysql/libmysqlclient.so {self.instdir}/lib/
            """), copy_libmysql_script)
            self.node.exec(f'chmod +x {copy_libmysql_script}')
            with self.nixenv():
                self.node.exec(copy_libmysql_script)
        self.copy_deps(self.instdir,
                       excludedirs=f'{self.pgdir}/lib:{self.pgdir}/lib/copied',
                       copyinterp=False,
                       checkdeps=False)
        self.copy_instscript(self.packdir)
        self.archive(self.packdir, self.pkgname)

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
        with self.node.dir(self.codedir):
            if self.options.progname == 'postgis':
                result = self.node.exec('cat Version.config')
                major = result.getfield('POSTGIS_MAJOR_VERSION=', 2, sep='=')
                minor = result.getfield('POSTGIS_MINOR_VERSION=', 2, sep='=')
                micro = result.getfield('POSTGIS_MICRO_VERSION=', 2, sep='=')
                return f'{major}.{minor}.{micro}'
            if self.options.progname == 'mysql_fdw':
                return self.node.exec('cat mysql_fdw.c | grep "version is"').split()[4]
            if self.options.progname == 'oracle_fdw':
                return self.node.exec('cat oracle_fdw.h | grep ORACLE_FDW_VERSION').split()[-1].strip('"')
            if self.options.progname == 'pgvector':
                return self.node.exec('cat vector.control').getfield('default_version', 2, sep='=').strip("'")
            return self.node.exec(f'cat {self.options.progname}.control').getfield('default_version', 2, sep='=').strip("'")
