import unittest
from types import SimpleNamespace

from pipelines.common.pack import pack
from pipelines.pack_postgres import pack_postgres


class PackHarness(pack):
    def copy_tests(self) -> None:
        self.events.append('copy_tests')


def make_pack(include_tests: bool) -> PackHarness:
    pipeline = object.__new__(PackHarness)
    pipeline.options = SimpleNamespace(include_tests=include_tests)
    pipeline.events = []
    return pipeline


class PostgresHarness(pack_postgres):
    @property
    def pkgname(self) -> str:
        return 'postgres.tar.gz'

    def copy_deps(self) -> None:
        self.events.append('copy_deps')

    def copy_instscript(self, destdir: str) -> None:
        self.events.append(('copy_instscript', destdir))

    def copy_tests(self) -> None:
        self.events.append('copy_tests')

    def prepare_tests(self) -> None:
        self.events.append('prepare_tests')
        super().prepare_tests()

    def archive(self, directory: str, pkgname: str | None = None) -> None:
        self.events.append(('archive', directory, pkgname))


def make_postgres(include_tests: bool) -> PostgresHarness:
    pipeline = object.__new__(PostgresHarness)
    pipeline.options = SimpleNamespace(include_tests=include_tests)
    pipeline.packdir = 'package'
    pipeline.testsdir = 'package/content/tests'
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

class PostgresStage3Test(unittest.TestCase):
    def test_embeds_tests_before_single_archive_when_enabled(self) -> None:
        pipeline = make_postgres(True)

        pipeline.stage3()

        self.assertEqual(
            pipeline.events,
            [
                'copy_deps',
                ('copy_instscript', 'package'),
                'prepare_tests',
                'copy_tests',
                ('archive', 'package', 'postgres.tar.gz'),
            ],
        )

    def test_archives_program_without_tests_when_disabled(self) -> None:
        pipeline = make_postgres(False)

        pipeline.stage3()

        self.assertEqual(
            pipeline.events,
            [
                'copy_deps',
                ('copy_instscript', 'package'),
                'prepare_tests',
                ('archive', 'package', 'postgres.tar.gz'),
            ],
        )


if __name__ == '__main__':
    unittest.main()
