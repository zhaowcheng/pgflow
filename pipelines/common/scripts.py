"""
公共脚本。
"""

from typing import Optional
from pathlib import PurePosixPath

from xflow.framework.node import Node, CommandResult


def copy_deps(
    node: Node,
    elfdir: str | PurePosixPath,
    destdir: str | PurePosixPath,
    excludedirs: Optional[str] = None
) -> CommandResult:
    """
    把 `elfdir` 目录中的所有 elf 文件的依赖库拷贝到 `destdir` 中。

    :param node: 执行节点。
    :param elfdir: elf 文件目录。
    :param destdir: 依赖库拷贝的目的目录。
    :param excludedirs: 拷贝前需要判断是否已存在 so 的目录列表。
    :return: 脚本输出。
    """
    if excludedirs:
        argstr = f'{elfdir} {destdir} {excludedirs}'
    else:
        argstr = f'{elfdir} {destdir}'
    return node.exec_script('scripts/copy_deps.sh', argstr=argstr)


def check_deps(
    node: Node,
    elfdir: str | PurePosixPath,
    ldpaths: Optional[str] = None
) -> CommandResult:
    """
    检查 `elfdir` 目录中的所有 elf 文件的依赖库是否都能找到。

    :param node: 执行节点。
    :param elfdir: elf 文件目录。
    :param ldpaths: 添加到 LD_LIBRARY_PATH 环境变量的路径。
    :return: 脚本输出。
    """
    envs = {'LD_LIBRARY_PATH': ldpaths} if ldpaths is not None else None
    return node.exec_script('scripts/check_deps.sh',
                            argstr=f'{elfdir}',
                            envs=envs)


def set_rpath(
    node: Node,
    elfdir: str | PurePosixPath,
    libdirs: str | PurePosixPath
) -> CommandResult:
    """
    把 `elfdir` 目录中的所有 elf 文件的 RPATH 设置为 `libdir`（相对路径）。

    :param node: 执行节点。
    :param elfdir: elf 文件目录。
    :param libdirs: 依赖库目录列表（以`:`分割）。
    :return: 脚本输出。
    """
    return node.exec_script('scripts/set_rpath.sh',
                            argstr=f'{elfdir} {libdirs}')


def set_interp(
    node: Node,
    elfdir: str | PurePosixPath,
    interp: str | PurePosixPath
) -> CommandResult:
    """
    把 `elfdir` 目录中的所有 elf 文件的动态库链接解释器设置为 `interp`。

    :param node: 执行节点。
    :param elfdir: elf 文件目录。
    :param interp: 动态库链接解释器路径。
    :return: 脚本输出。
    """
    return node.exec_script('scripts/set_interp.sh',
                            argstr=f'{elfdir} {interp}')


def wrap_runtime(
    node: Node,
    elfdir: str | PurePosixPath,
    locale_archive_savedir: str | PurePosixPath,
    pythondir: Optional[str | PurePosixPath] = None
) -> CommandResult:
    """
    把 `elfdir` 目录中的可执行程序替换为 shell 脚本并自动设置运行时环境变量。

    :param node: 执行节点。
    :param elfdir: elf 文件目录。
    :param locale_archive_savedir: locale-archive 相对 `elfdir` 的存放目录。
    :param pythondir: 可选的 Python 标准库目录。
    :return: 脚本输出。
    """
    argstr = f'{elfdir} {locale_archive_savedir}'
    if pythondir is not None:
        argstr += f' {pythondir}'
    return node.exec_script('scripts/wrap_runtime.sh',
                            argstr=argstr)


def copy_python(
    node: Node,
    destdir: str | PurePosixPath
) -> CommandResult:
    """
    把构建环境的 Python 标准库拷贝到 `destdir`。

    :param node: 执行节点。
    :param destdir: Python 标准库目标目录。
    :return: 脚本输出。
    """
    return node.exec_script('scripts/copy_python.sh',
                            argstr=f'{destdir}')
