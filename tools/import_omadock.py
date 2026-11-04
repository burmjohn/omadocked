#!/usr/bin/python3
"""Preview or apply an Omadock config import. Preview is the default and never writes."""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "services"))
import omadock_import  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dock", type=Path, help="Legacy dock.json (defaults to existing ~/.config/omarchy/dock.json)")
    parser.add_argument("--settings", type=Path, help="Legacy settings (defaults to existing ~/.config/omarchy/omadock.json)")
    parser.add_argument("--dest", type=Path, help="Omadocked pins.json for --apply only")
    parser.add_argument("--apply", action="store_true", help="Write dest after backup; refused without --dest")
    args = parser.parse_args()
    for name, filename in (("dock", "dock.json"), ("settings", "omadock.json")):
        if getattr(args, name) is None:
            default = Path.home() / ".config/omarchy" / filename
            if default.is_file():
                setattr(args, name, default)
    if args.apply:
        if args.dest is None:
            parser.error("--apply requires --dest")
        try:
            result = omadock_import.apply(args.dock, args.settings, args.dest)
        except (ValueError, OSError) as error:
            parser.error(str(error))
    else:
        result = omadock_import.preview(args.dock, args.settings)
    json.dump(result, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0 if not args.apply or result.get("applied") else 3


if __name__ == "__main__":
    raise SystemExit(main())
