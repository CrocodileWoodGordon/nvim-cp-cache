#!/usr/bin/env python3
"""Deploy a test copy and run Neovim with all generated data under its config."""
import hashlib
import difflib
import json
import os
import resource
import runpy
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
    if (REPO / "nvim.log").exists():
        (REPO / "nvim.log").replace(VERIFY / "reports/bootstrap-nvim.log")
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
            "NVIM_LOG_FILE": str(VERIFY / "reports/nvim.log"),
            "CP_CACHE_TEST_ROOT": str(VERIFY), "CP_CACHE_PLUGIN": str(COPY)}


def main():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    env = prepare()
    suite = sys.argv[1] if len(sys.argv) > 1 else "run"
    if suite == "install":
        updater = runpy.run_path(str(REPO / "integration/changes.py"))["update"]
        manifest = json.loads((BACKUP / "manifest.json").read_text())
        installed_path = BACKUP / "installed.json"
        installed = json.loads(installed_path.read_text()) if installed_path.exists() else {}
        changes, patch = {}, []
        for name in TARGETS:
            current = (CONFIG / name).read_bytes()
            if hashlib.sha256(current).hexdigest() not in (manifest[name], installed.get(name)):
                raise RuntimeError("Concurrent user change; integration refused: " + name)
            original = (BACKUP / name).read_text()
            updated = updater(name, original)
            changes[name] = (current, updated.encode())
            patch.extend(difflib.unified_diff(original.splitlines(True), updated.splitlines(True), fromfile="a/" + name, tofile="b/" + name))
        (REPO / "integration/nvim.patch").write_text("".join(patch))
        for name, (reviewed, data) in changes.items():
            target = CONFIG / name
            if target.read_bytes() != reviewed:
                raise RuntimeError("Concurrent user change; write refused: " + name)
            if data != reviewed:
                temporary = target.with_name(target.name + ".cp-cache-tmp")
                temporary.write_bytes(data)
                temporary.chmod(target.stat().st_mode)
                temporary.replace(target)
            installed[name] = hashlib.sha256(data).hexdigest()
        installed_path.write_text(json.dumps(installed, indent=2) + "\n")
        print("Installed reviewed NvChad changes; backup: " + str(BACKUP))
        return 0
    test_file = suite
    if suite in ("store", "workflow", "receiver"):
        env["CP_CACHE_SUITE"] = suite
        test_file = "run"
    init = "lazy_init" if suite == "lazy_probe" else "minimal_init"
    if suite in ("baseline", "full", "gdb"):
        theme = subprocess.run(["nvim", "--headless", "-i", "NONE", "-u", "NONE", "-l", str(COPY / "tests/theme.lua")], env=env, capture_output=True, timeout=30)
        if theme.returncode:
            print(theme.stderr.decode(errors="replace")); return theme.returncode
        fixture = VERIFY / "fixtures/full/main.cpp"
        fixture.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(CONFIG / "examples/cp-demo/main.cpp", fixture)
        env["CP_CACHE_FULL_MODE"] = suite
        command = ["nvim", "--headless", "-i", "NONE", "-u", str(CONFIG / "init.lua"), str(fixture),
                   "-c", "lua dofile(vim.env.CP_CACHE_PLUGIN .. '/tests/full.lua')"]
    else:
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
