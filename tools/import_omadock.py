#!/usr/bin/python3
"""Preview or apply an Omadock config import. Preview is the default and never writes."""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "services"))
import omadock_import  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dock", type=Path, default=Path.home() / ".config/omarchy/dock.json")
    parser.add_argument("--settings", type=Path, default=Path.home() / ".config/omarchy/omadock.json")
    parser.add_argument("--dest", type=Path, help="Omadocked pins.json for --apply only")
    parser.add_argument("--apply", action="store_true", help="Write dest after backup; refused without --dest")
    args = parser.parse_args()
    if args.apply:
        if args.dest is None:
            parser.error("--apply requires --dest")
        result = omadock_import.apply(args.dock, args.settings, args.dest)
    else:
        result = omadock_import.preview(args.dock if args.dock.is_file() else None,
                                        args.settings if args.settings.is_file() else None)
    json.dump(result, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
