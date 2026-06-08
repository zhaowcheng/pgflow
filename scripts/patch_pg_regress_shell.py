#!/usr/bin/env python3
"""Allow packaged pg_regress to use a relocatable shell path."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def patch_pg_regress(pg_regress: Path) -> None:
    text = pg_regress.read_text()
    replacements = (
        (
            "static char *shellprog = SHELLPROG;",
            "static char *shellprog = NULL;",
        ),
        (
            '\n\t\tcmdline2 = psprintf("exec %s", cmdline);',
            '\n\t\tif (shellprog == NULL)\n'
            "\t\t{\n"
            '\t\t\tshellprog = getenv("PG_TEST_SHELL");\n'
            "\t\t\tif (shellprog == NULL || shellprog[0] == '\\0')\n"
            "\t\t\t\tshellprog = SHELLPROG;\n"
            "\t\t}\n"
            "\n"
            '\t\tcmdline2 = psprintf("exec %s", cmdline);',
        ),
    )

    for old, new in replacements:
        if old not in text:
            raise RuntimeError(f"patch target not found: {old!r}")
        text = text.replace(old, new, 1)

    pg_regress.write_text(text)

    if "PG_TEST_SHELL" not in text:
        raise RuntimeError("patch verification failed: PG_TEST_SHELL not found")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Patch PostgreSQL pg_regress to use PG_TEST_SHELL when set.",
    )
    parser.add_argument(
        "srcdir",
        type=Path,
        metavar="POSTGRES_SOURCE_DIR",
        help="PostgreSQL source directory.",
    )
    args = parser.parse_args()

    pg_regress = args.srcdir / "src/test/regress/pg_regress.c"
    if not pg_regress.is_file():
        print(f"error: pg_regress.c not found: {pg_regress}", file=sys.stderr)
        return 1

    try:
        patch_pg_regress(pg_regress)
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
