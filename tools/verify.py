#!/usr/bin/env python3
"""Deploy a test copy and run Neovim with all generated data under its config."""
import hashlib
import json
import os
import resource
from pathlib import Path
import shutil
import subprocess
import sys

REPO = Path(__file__).resolve().parent.parent
CONFIG = Path.home() / ".config/nvim"
VERIFY = CONFIG / ".verify/cp-cache"
COPY = CONFIG / "local/cp-cache.nvim"
BACKUP = CONFIG / "backups/cp-cache-2026-10-16"
TARGETS = ["lua/plugins/competitive.lua", "lua/cp/init.lua", "after/ftplugin/cpp.lua",
           "docs/competitive-programming.md"]


def prepare():
    for name in ("data", "state", "cache", "tmp", "fixtures", "store", "reports"):
        (VERIFY / name).mkdir(parents=True, exist_ok=True)
    BACKUP.mkdir(parents=True, exist_ok=True)
    manifest = BACKUP / "manifest.json"
    if not manifest.exists():
        entries = {}
        for name in TARGETS:
            source = CONFIG / name
            data = source.read_bytes()
            destination = BACKUP / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
            entries[name] = hashlib.sha256(data).hexdigest()
        manifest.write_text(json.dumps(entries, indent=2) + "\n")
    for name in ("lua", "plugin", "doc", "tests", "integration"):
        if (REPO / name).exists():
            shutil.copytree(REPO / name, COPY / name, dirs_exist_ok=True)
    return {**os.environ, "XDG_DATA_HOME": str(VERIFY / "data"),
            "XDG_STATE_HOME": str(VERIFY / "state"), "XDG_CACHE_HOME": str(VERIFY / "cache"),
            "TMPDIR": str(VERIFY / "tmp"), "NVIM_CP_OFFLINE": "1", "PYTHONDONTWRITEBYTECODE": "1",
            "CP_CACHE_TEST_ROOT": str(VERIFY), "CP_CACHE_PLUGIN": str(COPY)}


def main():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    env = prepare()
    suite = sys.argv[1] if len(sys.argv) > 1 else "run"
    test_file = suite
    if suite in ("store", "workflow", "receiver"):
        env["CP_CACHE_SUITE"] = suite
        test_file = "run"
    init = "lazy_init" if suite == "lazy_probe" else "minimal_init"
    command = ["nvim", "--headless", "-i", "NONE", "-u", str(COPY / ("tests/" + init + ".lua")),
               "-l", str(COPY / ("tests/" + test_file + ".lua"))]
    if "--gdb" in sys.argv[2:]:
        command = ["gdb", "--batch", "-nx", "-ex", "run", "-ex", "bt", "--args", *command]
    result = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
    (VERIFY / "reports" / (suite + ".log")).write_bytes(result.stdout)
    print(result.stdout.decode(errors="replace"), end="")
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
