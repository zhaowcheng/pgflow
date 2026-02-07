"""
公共脚本。
"""

from pathlib import PurePosixPath

from xflow.framework.node import Node, CommandResult


def copy_deps(
    node: Node,
    elfdir: str | PurePosixPath,
    libdir: str | PurePosixPath
) -> CommandResult:
    """
    把 `elfdir` 目录中的所有 elf 文件的依赖库拷贝到 `libdir` 中。

    :param node: 执行节点。
    :param elfdir: elf 文件目录。
    :param libdir: 依赖库目录。
    :return: 脚本输出。
    """
    return node.exec_script('scripts/copy_deps.sh',
                            argstr=f'{elfdir} {libdir}')


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
