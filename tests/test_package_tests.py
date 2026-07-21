import unittest
from types import SimpleNamespace

from pipelines.common.pack import pack


class PackHarness(pack):
    def copy_tests(self) -> None:
        self.events.append('copy_tests')


def make_pack(include_tests: bool) -> PackHarness:
    pipeline = object.__new__(PackHarness)
    pipeline.options = SimpleNamespace(include_tests=include_tests)
    pipeline.events = []
    return pipeline


class PrepareTestsTest(unittest.TestCase):
    def test_copies_tests_when_enabled(self) -> None:
        pipeline = make_pack(True)

        pipeline.prepare_tests()

        self.assertEqual(pipeline.events, ['copy_tests'])

    def test_skips_tests_when_disabled(self) -> None:
        pipeline = make_pack(False)

        pipeline.prepare_tests()

        self.assertEqual(pipeline.events, [])

    def test_base_class_has_no_separate_test_package_name(self) -> None:
        self.assertFalse(hasattr(pack, 'tests_pkgname'))


if __name__ == '__main__':
    unittest.main()
