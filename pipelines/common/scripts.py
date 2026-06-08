"""
公共脚本。
"""

from shlex import quote
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


def _join_colon(items: list[str] | tuple[str, ...]) -> str:
    """
    使用冒号连接参数，并转义条目内部的冒号。
    """
    return ':'.join(item.replace('\\', '\\\\').replace(':', '\\:')
                    for item in items)


def wrap_envs(
    node: Node,
    topdir: str | PurePosixPath,
    bins: list[str] | tuple[str, ...],
    envs: list[str] | tuple[str, ...]
) -> CommandResult:
    """
    把 `topdir` 下指定的可执行程序替换为 shell 脚本并自动设置环境变量。

    :param node: 执行节点。
    :param topdir: 目标目录。
    :param bins: 需要 wrap 的程序，相对 `topdir`。
    :param envs: 写入 wrapper 的环境变量，格式为 NAME=VALUE。
    :return: 脚本输出。
    """
    argstr = ' '.join(quote(item)
                      for item in (str(topdir), _join_colon(bins), _join_colon(envs)))
    return node.exec_script('scripts/wrap_envs.sh',
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


def copy_perl(
    node: Node,
    destdir: str | PurePosixPath
) -> CommandResult:
    """
    把构建环境的 Perl 库目录拷贝到 `destdir`。

    :param node: 执行节点。
    :param destdir: Perl 库目标目录。
    :return: 脚本输出。
    """
    return node.exec_script('scripts/copy_perl.sh',
                            argstr=f'{destdir}')


def copy_tcl(
    node: Node,
    destdir: str | PurePosixPath
) -> CommandResult:
    """
    把构建环境的 Tcl 库目录拷贝到 `destdir`。

    :param node: 执行节点。
    :param destdir: Tcl 库目标目录。
    :return: 脚本输出。
    """
    return node.exec_script('scripts/copy_tcl.sh',
                            argstr=f'{destdir}')


def copy_runtime_tools(
    node: Node,
    destdir: str | PurePosixPath,
    tools: list[str] | tuple[str, ...]
) -> CommandResult:
    """
    把构建环境 PATH 中的工具复制到 `destdir/bin`。

    :param node: 执行节点。
    :param destdir: 工具目录。
    :param tools: 工具名列表。
    :return: 脚本输出。
    """
    return node.exec_script('scripts/copy_runtime_tools.sh',
                            argstr=' '.join([str(destdir), *tools]))
