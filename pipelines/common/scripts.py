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
