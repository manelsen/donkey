#!/usr/bin/env python3
"""Compare two TEST_REPORT_DIR inventories and their per-file logs.

Usage: python3 scripts/compare_test_reports.py BEFORE AFTER

The runner writes ``index.tsv`` plus ``logs/<path>.log`` for every discovered
test file. This script compares file status/skip reasons and the multiset of
(suite, case, status) entries found in each log, so renamed, missing, extra or
duplicated cases are reported instead of silently ignored.

Exit codes: 0 identical, 1 differences, 2 invalid input/report.
"""

from __future__ import annotations

import collections
import pathlib
import re
import sys

ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
# std/unittest prints "[Suite] name" and "  [OK] name".
STD_SUITE = re.compile(r"^\s*\[Suite\]\s+(.*\S)\s*$")
# unittest2 verbose prints "[Suite  ] name" / "[OK     ] (0.00s) name".
UNITTEST2_SUITE = re.compile(r"^\s*\[Suite\s*\]\s+(.*\S)\s*$")
CASE = re.compile(
    r"^\s*\[(OK|FAILED|SKIPPED)\s*\]\s*"
    r"(?:\([^)]*\)\s*)?(.*\S)?\s*$"
)
EMPTY_ALLOWED = "tests/adapters/memory/t_hybrid_search.nim"
STATUS_NAMES = {"OK": "ok", "FAILED": "failed", "SKIPPED": "skipped"}


def clean(text: str) -> str:
    return ANSI.sub("", text).replace("\r", "")


def read_index(report: pathlib.Path) -> dict[str, tuple[str, str]]:
    index = report / "index.tsv"
    if not index.is_file():
        raise ValueError(f"{index}: missing inventory")
    files: dict[str, tuple[str, str]] = {}
    with index.open(encoding="utf-8", errors="replace") as handle:
        for lineno, raw in enumerate(handle, 1):
            line = clean(raw).rstrip("\n")
            if not line or line == "path\tstatus\treason":
                continue
            parts = line.split("\t", 2)
            if len(parts) < 2:
                raise ValueError(f"{index}:{lineno}: malformed line")
            path, status = parts[0], parts[1]
            reason = parts[2] if len(parts) == 3 else ""
            if status not in {"executed", "failed", "skipped"}:
                raise ValueError(f"{index}:{lineno}: unknown status {status!r}")
            files[path] = (status, reason)
    return files


def parse_cases(report: pathlib.Path, path: str) -> collections.Counter:
    log = report / "logs" / f"{path}.log"
    if not log.is_file():
        raise ValueError(f"{log}: missing log")
    cases: collections.Counter = collections.Counter()
    suite = "<none>"
    with log.open(encoding="utf-8", errors="replace") as handle:
        for raw in handle:
            line = clean(raw).rstrip("\n")
            suite_match = STD_SUITE.match(line) or UNITTEST2_SUITE.match(line)
            if suite_match:
                suite = suite_match.group(1).strip()
                continue
            case_match = CASE.match(line)
            if case_match:
                status = STATUS_NAMES[case_match.group(1)]
                name = (case_match.group(2) or "<unnamed>").strip()
                cases[(path, suite, name, status)] += 1
    return cases


def load(report: pathlib.Path) -> tuple[dict[str, tuple[str, str]], collections.Counter]:
    files = read_index(report)
    cases: collections.Counter = collections.Counter()
    empty_error = None
    for path, (status, _reason) in files.items():
        parsed = parse_cases(report, path)
        cases.update(parsed)
        if status == "executed" and not parsed and path != EMPTY_ALLOWED:
            empty_error = empty_error or (
                f"{report}: {path} is {status} but produced zero cases"
            )
    if empty_error:
        raise ValueError(empty_error)
    return files, cases


def describe(key: tuple[str, str, str, str]) -> str:
    path, suite, name, status = key
    return f"{path} :: {suite} :: {name} [{status}]"


def compare(before_dir: pathlib.Path, after_dir: pathlib.Path) -> int:
    before_files, before_cases = load(before_dir)
    after_files, after_cases = load(after_dir)
    problems = 0

    for path in sorted(before_files.keys() - after_files.keys()):
        print(f"missing file after: {path}")
        problems += 1
    for path in sorted(after_files.keys() - before_files.keys()):
        print(f"extra file after: {path}")
        problems += 1

    for path in sorted(before_files.keys() & after_files.keys()):
        old_status, old_reason = before_files[path]
        new_status, new_reason = after_files[path]
        if old_status != new_status or old_reason != new_reason:
            print(
                f"file changed: {path} "
                f"[{old_status} {old_reason!r} -> {new_status} {new_reason!r}]"
            )
            problems += 1

    for key in sorted(before_cases.keys() | after_cases.keys()):
        old_count = before_cases.get(key, 0)
        new_count = after_cases.get(key, 0)
        if old_count != new_count:
            print(f"case count: {describe(key)} before={old_count} after={new_count}")
            problems += 1

    if problems:
        print(
            f"\n{problems} difference(s); "
            f"{sum(before_cases.values())} cases before, "
            f"{sum(after_cases.values())} after"
        )
        return 1
    print(
        f"Reports match: {len(before_files)} files, "
        f"{sum(before_cases.values())} cases"
    )
    return 0


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    try:
        return compare(pathlib.Path(argv[1]), pathlib.Path(argv[2]))
    except (OSError, ValueError) as exc:
        print(f"compare_test_reports: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
