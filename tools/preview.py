"""Launch the standalone preview through the hosted persistence path.

The QML-owned Process starts the same long-lived helper used by a shared shell.
This launcher never acquires or inherits a configuration lock.
"""
import argparse
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config-path", help="literal absolute persistent JSON path")
    parser.add_argument("args", nargs=argparse.REMAINDER, help="Quickshell options after -- (no daemon)")
    args = parser.parse_args()
    options = args.args[1:] if args.args[:1] == ["--"] else args.args
    if any(option in ("-d", "--daemonize") or (option.startswith("-") and not option.startswith("--") and "d" in option) for option in options):
        parser.error("daemon mode is unsupported by the owned preview lifecycle")
    env = {key: value for key, value in os.environ.items()
           if key not in ("OMADOCKED_WRITER_FD", "OMADOCKED_WRITER_PID",
                          "OMADOCKED_BOOTSTRAP_FD", "OMADOCKED_WRITER_PRELOAD")}
    if args.config_path is not None:
        env["OMADOCKED_CONFIG_PATH"] = args.config_path
    os.execvpe("quickshell", ["quickshell", *(options or ["-n", "-p", str(ROOT / "shell.qml")])], env)


if __name__ == "__main__":
    raise SystemExit(main())
