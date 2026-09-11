"""Owned desktop-action receipt; no windows, shell, or user files."""
import json
import os
from pathlib import Path
import sys

receipt, lock = Path(sys.argv[1]), Path(sys.argv[2])
inherited_lock = False
for fd in Path("/proc/self/fd").iterdir():
    try:
        inherited_lock |= os.readlink(fd) == str(lock)
    except OSError:
        pass  # The descriptor used to enumerate /proc may already be closed.
writer_keys = ("OMADOCKED_WRITER_PID", "OMADOCKED_WRITER_FD",
               "OMADOCKED_BOOTSTRAP_FD", "OMADOCKED_WRITER_PRELOAD")
receipt.write_text(json.dumps({"cwd": os.getcwd(), "args": sys.argv[3:],
                               "writer_metadata": any(k in os.environ for k in writer_keys),
                               "writer_lock": inherited_lock}))
