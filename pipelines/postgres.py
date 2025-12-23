import textwrap

from typing import Optional

from xflow.framework.pipeline import Pipeline
from .common.options import RepoOptions
from .common.scripts import copy_deps, set_rpath, set_interp


class postgres(Pipeline):
    """
    postgres 打包流程。
    """
    class Options(RepoOptions):
        """
        流水线参数表。
        """
        system: str = Pipeline.Option(desc='The target system to build.',
                                      choices=('x86_64-linux', 'aarch64-linux', 'loongarch64-linux', 'mips64el-linux'))

        # PostgreSQL Features
        enable_nls: Optional[str] = Pipeline.Option(desc='Enables Native Language Support (NLS).')
        with_perl: bool = Pipeline.Option(desc='Build the PL/Perl server-side language.',
                                          default=False)
        with_python: bool = Pipeline.Option(desc='Build the PL/Python server-side language.',
                                            default=False)
        with_tcl: bool = Pipeline.Option(desc='Build the PL/Tcl server-side language.',
                                         default=False)
        with_llvm: bool = Pipeline.Option(desc='Build with support for LLVM based JIT compilation.',
                                          default=False)
        with_lz4: bool = Pipeline.Option(desc='Build with LZ4 compression support.',
                                         default=False)
        with_zstd: bool = Pipeline.Option(desc='Build with Zstandard compression support.',
                                          default=False)
        with_ssl: Optional[str] = Pipeline.Option(desc='Build with support for SSL (encrypted) connections', 
                                        choices=('openssl',))
        with_gssapi: bool = Pipeline.Option(desc='Build with support for GSSAPI authentication.',
                                            default=False)
        with_ldap: bool = Pipeline.Option(desc='Build with LDAP support for authentication and connection parameter lookup.',
                                          default=False)
        with_pam: bool = Pipeline.Option(desc='Build with PAM (Pluggable Authentication Modules) support.',
                                         default=False)
        with_bsd_auth: bool = Pipeline.Option(desc='Build with BSD Authentication support.',
                                              default=False)
        with_systemd: bool = Pipeline.Option(desc='Build with support for systemd service notifications.',
                                             default=False)
        with_bonjour: bool = Pipeline.Option(desc='Build with support for Bonjour automatic service discovery.',
                                             default=False)
        with_uuid: Optional[str] = Pipeline.Option(desc='Build the uuid-ossp module (which provides functions to generate UUIDs), using the specified UUID library)',
                                                   choices=('bsd', 'e2fs', 'ossp'))
        with_libcurl: bool = Pipeline.Option(desc='Build with libcurl support for OAuth 2.0 client flows.',
                                             default=False)
        with_libnuma: bool = Pipeline.Option(desc='Build with libnuma support for basic NUMA support.',
                                             default=False)
        with_liburing: bool = Pipeline.Option(desc='Build with liburing, enabling io_uring support for asynchronous I/O.',
                                              default=False)
        with_libxml: bool = Pipeline.Option(desc='Build with libxml2, enabling SQL/XML support.',
                                            default=False)
        with_libxslt: bool = Pipeline.Option(desc='Build with libxslt, enabling the xml2 module to perform XSL transformations of XML.',
                                             default=False)
        with_selinux: bool = Pipeline.Option(desc='Build with SElinux support, enabling the sepgsql extension.',
                                             default=False)

        # Anti-Features 
        without_icu: bool = Pipeline.Option(desc='Build without support for the ICU library, disabling the use of ICU collation features.',
                                            default=False)
        without_readline: bool = Pipeline.Option(desc='Prevents use of the Readline library (and libedit as well).',
                                                 default=False)
        with_libedit_preferred: bool = Pipeline.Option(desc='Favors the use of the BSD-licensed libedit library rather than GPL-licensed Readline.',
                                                       default=False)
        without_zlib: bool = Pipeline.Option(desc='Prevents use of the Zlib library',
                                             default=False)

        # Miscellaneous
        with_pgport: Optional[int] = Pipeline.Option(desc='Set the default port number for server and clients.')
        with_krb_srvnam: Optional[str] = Pipeline.Option(desc='The default name of the Kerberos service principal used by GSSAPI.')
        with_segsize: Optional[int] = Pipeline.Option(desc='Set the segment size, in gigabytes.')
        with_blocksize: Optional[int] = Pipeline.Option(desc='Set the block size, in kilobytes.')
        with_wal_blocksize: Optional[int] = Pipeline.Option(desc='Set the WAL block size, in kilobytes.')

        # Developer Options 
        enable_debug: bool = Pipeline.Option(desc='Compiles all programs and libraries with debugging symbols.',
                                             default=False)
        enable_cassert: bool = Pipeline.Option(desc='Enables assertion checks in the server, which test for many “cannot happen” conditions.',
                                               default=False)
        enable_tap_tests : bool = Pipeline.Option(desc='Enable tests using the Perl TAP tools.',
                                                  default=False)
        enable_depend: bool = Pipeline.Option(desc='Enables automatic dependency tracking.',
                                              default=False)
        enable_coverage: bool = Pipeline.Option(desc='If using GCC, all programs and libraries are compiled with code coverage testing instrumentation.',
                                                default=False)
        enable_profiling: bool = Pipeline.Option(desc='If using GCC, all programs and libraries are compiled so they can be profiled.',
                                                 default=False)
        enable_dtrace: bool = Pipeline.Option(desc='Compiles PostgreSQL with support for the dynamic tracing tool DTrace.',
                                              default=False)
        enable_injection_points: bool = Pipeline.Option(desc='Compiles PostgreSQL with support for injection points in the server.',
                                                        default=False)
        with_segsize_blocks: Optional[int] = Pipeline.Option(desc='Specify the relation segment size in blocks.')

    def setup(self) -> None:
        """
        前置步骤。
        """
        self.options: __class__.Options  # 保留用于自动提示
        super().setup()

        # 编译参数准备
        self.instdir = self.node.cwd.joinpath('install')
        self.configure_options = [f'--prefix={self.instdir}']
        # 处理 bool 类型参数
        for name in ('with_perl',
                     'with_python',
                     'with_tcl',
                     'with_llvm',
                     'with_lz4',
                     'with_zstd',
                     'with_gssapi',
                     'with_ldap',
                     'with_pam',
                     'with_bsd_auth',
                     'with_systemd',
                     'with_bonjour',
                     'with_libcurl',
                     'with_libnuma',
                     'with_liburing',
                     'with_libxml',
                     'with_libxslt',
                     'with_selinux',
                     'without_icu',
                     'without_readline',
                     'with_libedit_preferred',
                     'without_zlib',
                     'enable_debug',
                     'enable_cassert',
                     'enable_tap_tests',
                     'enable_depend',
                     'enable_coverage',
                     'enable_profiling',
                     'enable_dtrace',
                     'enable_injection_points',
                    ):
            if self.options.model_dump().get(name):
                self.configure_options.append(f'--{name.replace("_", "-")}')
        # 处理 str 和 int 类型参数。
        for name in ('enable_nls',
                     'with_ssl',
                     'with_uuid',
                     'with_pgport',
                     'with_krb_srvnam',
                     'with_segsize',
                     'with_blocksize',
                     'with_wal_blocksize',
                     'with_segsize_blocks',
                     ):
            value = self.options.model_dump().get(name)
            if value is not None:
                # enable_nls 参数后可以不指定值。
                if value == '' and name == 'enable_nls':
                    self.configure_options.append(f'--{name.replace("_", "-")}')
                else:
                    self.configure_options.append(f'--{name.replace("_", "-")}={value}')

    def stage1(self) -> None:
        """
        拉取代码。
        """
        self.node.git(self.options.repo_url,
                      self.options.revision,
                      directory='code')
        
    def stage2(self) -> None:
        """
        编译。
        """
        with self.node.dir('code'):
            with self.node.nixenv('~/flakes', 
                                  system=self.options.system, 
                                  name='postgres'):
                self.node.exec(f'./configure {" ".join(self.configure_options)}')
                self.node.exec('make -l -j`nproc` world')
                self.node.exec('make install-world')

    def stage3(self) -> None:
        """
        打包。
        """
        libdir = self.instdir.joinpath('lib')
        bindir = self.instdir.joinpath("bin")
        postgres = bindir.joinpath('postgres')
        scriptsdir = self.instdir.joinpath('scripts')
        self.node.exec(f'mkdir {scriptsdir}')
        with self.node.nixenv('~/flakes', 
                              system=self.options.system, 
                              name='postgres'):
            # 查询版本号
            version = self.node.exec(f'{bindir}/postgres --version').getfield('postgres', 3)
            # 拷贝依赖
            copy_deps(self.node, self.instdir, libdir)
            # 添加写权限，避免设置 RPATH 失败
            self.node.exec(f'chmod +w -R {libdir}')
            # 设置 RPATH
            set_rpath(self.node, self.instdir, libdir)
            # 设置 interpreter
            interp_path = self.node.exec(f'patchelf --print-interpreter {postgres}')
            interp_name = interp_path.split('/')[-1]
            self.node.exec(f'cp {interp_path} {libdir}')
            set_interp(self.node, bindir, f'./lib/{interp_name}')
            # 拷贝 patchelf
            patchelf = self.node.exec('which patchelf')
            self.node.exec(f'cp {patchelf} {scriptsdir}')
        # 创建配置脚本和说明
        self.node.putfile('scripts/setup.sh', scriptsdir)
        self.node.exec(f'chmod +x {scriptsdir}/setup.sh')
        self.node.write(textwrap.dedent("""
        1、本安装包自带了所有依赖（包括 glibc），并且为所有 ELF 文件设置了 RPATH 
           自动查找自带的依赖，所以无需配置 LD_LIBRARY_PATH 即可使用，而且配置
           LD_LIBRARY_PATH 后反而会导致系统命令错误的引用了 lib 中的 glibc 等
           基础库而出错。
        2、打包时已把所有 bin 目录下的程序的 interpreter 设置为指向 lib 目录中 
           interpreter 的相对路径，所以一开始只能在解压后的目录下执行程序才可成功
          （如 ./bin/postgre），解压完成后请执行 scripts/setup.sh 脚本进行初始
           配置，配置完成后会把 interpreter 修改为绝对路径，如果按照路径发生的变更，
           需重新执行 scripts/setup.sh 脚本。
        """), f'{self.instdir.joinpath("README")}')
        # 打包下载
        tarname = f'postgres-{version}-{self.options.system}.tar.gz'
        self.node.exec(f'tar czvf {tarname} -C {self.instdir} .')
        tarpath = self.node.cwd.joinpath(tarname)
        self.node.getfile(tarpath, self.cwd)

    def teardown(self) -> None:
        """
        后置步骤。
        """
        super().teardown()
