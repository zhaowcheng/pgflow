import shlex
import unittest
from pipelines.common.scripts import wrap_envs


class FakeNode:
    def __init__(self) -> None:
        self.script = ""
        self.argstr = ""

    def exec_script(self, script: str, argstr: str):
        self.script = script
        self.argstr = argstr
        return "result"


class WrapEnvsTests(unittest.TestCase):
    def test_forwards_bindir_and_all_envs(self) -> None:
        node = FakeNode()
        result = wrap_envs(
            node, "/package root", "tools/bin",
            ("A=one:two", "B=$TOPDIR/lib"),
        )
        self.assertEqual(result, "result")
        self.assertEqual(node.script, "scripts/wrap_envs.sh")
        self.assertEqual(
            shlex.split(node.argstr),
            ["/package root", "tools/bin", r"A=one\:two:B=$TOPDIR/lib"],
        )


if __name__ == "__main__":
    unittest.main()
