"""Owned fixture for explicit argv/cwd launch tests; never imported by production."""
import json
import os
from pathlib import Path
import sys

if __name__ == "__main__":
    receipt = Path(sys.argv[1])
    if not receipt.is_absolute() or receipt.parent.resolve() != Path.cwd():
        raise SystemExit("Receipt must be inside the explicitly selected fixture working directory")
    fds = []
    for fd in Path("/proc/self/fd").iterdir():
        try: fds.append(os.readlink(fd))
        except OSError: pass
    assert not any(value.endswith(".lock") or "writer_fd.so" in value for value in fds)
    assert not any(key.startswith("OMADOCKED_WRITER_") or key == "OMADOCKED_BOOTSTRAP_FD" for key in os.environ)
    assert "writer_fd" not in os.environ.get("LD_PRELOAD", "") and "/proc/self/fd/" not in os.environ.get("LD_PRELOAD", "")
    receipt.write_text(json.dumps({"cwd": os.getcwd(), "args": sys.argv[2:]}))
