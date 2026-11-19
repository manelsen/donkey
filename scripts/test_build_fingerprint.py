#!/usr/bin/env python3
"""Fingerprint the toolchain and inputs used to compile grouped tests."""

import hashlib
import os
import platform
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
NIM_FILES = {".nim", ".nims", ".nimble"}
NATIVE_FILES = {".cfg", ".c", ".h", ".cc", ".cpp", ".inc", ".s", ".S", ".m", ".mm"}


def add(digest, value):
    digest.update(len(value).to_bytes(8, "big"))
    digest.update(value)


def add_file(digest, path):
    if not path.is_file():
        return
    contents = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            contents.update(chunk)
    add(digest, os.fsencode(path))
    add(digest, contents.digest())


def add_tree(digest, root, suffixes=None):
    if not root.is_dir():
        return
    for directory, dirs, files in os.walk(root):
        dirs[:] = sorted(name for name in dirs if name != ".git")
        for name in sorted(files):
            path = Path(directory, name)
            if name != ".git" and (suffixes is None or path.suffix in suffixes):
                add_file(digest, path)


def main():
    profile = hashlib.sha256()
    system = platform.system()
    for value in (str(ROOT), system, platform.machine()):
        add(profile, os.fsencode(value))
    for name in ("EXTRA_NIM_FLAGS", "NIMFLAGS", "CC", "CFLAGS", "CPPFLAGS",
                 "LDFLAGS", "SDKROOT", "MACOSX_DEPLOYMENT_TARGET"):
        add(profile, os.fsencode(os.environ.get(name, "")))
    tools = ("nim", "cc", "gcc", "clang", "ld") if system == "Linux" else (
        "nim", "cc", "gcc", "clang")
    for tool in tools:
        executable = shutil.which(tool)
        if executable:
            add(profile, os.fsencode(executable))
            add(profile, subprocess.check_output([executable, "--version"], cwd=ROOT))
    if system == "Linux":
        # Hosted runners can rotate between image revisions with the same ABI.
        add_file(profile, Path("/etc/os-release"))
        cc = shutil.which("gcc") or shutil.which("cc")
        if cc:
            for library in ("libc.so.6", "libgcc_s.so.1", "libssl.so", "libcrypto.so"):
                location = subprocess.check_output(
                    [cc, "-print-file-name=" + library], cwd=ROOT, text=True).strip()
                add_file(profile, Path(location))
    home = Path.home()
    config_home = Path(os.environ.get("XDG_CONFIG_HOME") or home / ".config")
    for path in (home / ".nim.cfg", config_home / "nim/nim.cfg",
                 config_home / "nim/config.nims", Path("/etc/nim/nim.cfg"),
                 Path("/etc/nim/config.nims")):
        add_file(profile, path)
    add_tree(profile, home / ".nimble/pkgs2")
    for name in ("config.nims", "nim.cfg", "donkey.nimble", "test_flags.nims",
                 "scripts/run_tests.sh", "scripts/test_build_fingerprint.py",
                 "sqlite3.c", "sqlite-vec.c"):
        add_file(profile, ROOT / name)
    add_tree(profile, ROOT / "vendor")
    for directory in ("src", "tests"):
        add_tree(profile, ROOT / directory, NATIVE_FILES)

    inputs = profile.copy()
    for directory in ("src", "tests"):
        add_tree(inputs, ROOT / directory, NIM_FILES)
    add_tree(inputs, ROOT / "tests/fixtures")
    manifest = os.environ.get("TEST_GROUP_MANIFEST") or "tests/test_groups.tsv"
    add_file(inputs, ROOT / manifest)
    print(profile.hexdigest(), inputs.hexdigest())


if __name__ == "__main__":
    main()
