"""Drive a real Neovim terminal through two SIGWINCH size changes, without deps."""
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import signal
import struct
import sys
import termios
import time
import uuid

root = Path(os.environ["CP_CACHE_TEST_ROOT"])
ready = root / "reports" / ("resize-" + uuid.uuid4().hex)
result = ready.with_suffix(".json")
env = {**os.environ, "TERM": "xterm-256color", "CP_CACHE_RESIZE_READY": str(ready), "CP_CACHE_RESIZE_RESULT": str(result)}
pid, fd = pty.fork()
if pid == 0:
    plugin = os.environ["CP_CACHE_PLUGIN"]
    os.execvpe("nvim", ["nvim", "-i", "NONE", "-u", plugin + "/tests/minimal_init.lua",
                        "-c", "lua dofile(vim.env.CP_CACHE_PLUGIN .. '/tests/resize.lua')"], env)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
transcript = bytearray()
stage = ""
status = None
deadline = time.monotonic() + 60
while time.monotonic() < deadline:
    if ready.exists():
        next_stage = ready.read_text()
        if next_stage != stage:
            stage = next_stage
            rows, columns = (38, 110) if stage == "runner" else (34, 100)
            fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))
            os.kill(pid, signal.SIGWINCH)
    readable, _, _ = select.select([fd], [], [], 0.05)
    if readable:
        try:
            transcript.extend(os.read(fd, 65536))
        except OSError:
            pass
    ended, child_status = os.waitpid(pid, os.WNOHANG)
    if ended:
        status = os.waitstatus_to_exitcode(child_status)
        break
if status is None:
    os.kill(pid, signal.SIGKILL)
    os.waitpid(pid, 0)
    status = 1
os.close(fd)
(root / "reports/resize-tui.log").write_bytes(transcript)
if status != 0 or not result.exists():
    print("Real TUI resize FAIL; see " + str(root / "reports/resize-tui.log"))
    sys.exit(1)
evidence = json.loads(result.read_text())
assert evidence["status"] == "PASS"
print("P5 TUI PASS: actual runner resize to 110x38, editor resize to 100x34, content and save callback preserved")
