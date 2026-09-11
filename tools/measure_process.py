"""Read-only Linux exact-PID CPU/RSS sampling, not an idle or FPS claim."""
import argparse
import json
import math
import os
from pathlib import Path
import time


def parse_stat(text, page_size):
    pid, _, rest = text.partition(" (")
    _, marker, fields = rest.rpartition(") ")
    if not marker:
        raise ValueError("Invalid /proc stat record")
    fields = fields.split()
    return {"pid": int(pid), "start_ticks": int(fields[19]),
            "cpu_ticks": int(fields[11]) + int(fields[12]),
            "rss_bytes": int(fields[21]) * page_size}


def summarize(samples, elapsed, ticks_per_second):
    if len(samples) < 2 or elapsed <= 0 or not math.isfinite(elapsed) or ticks_per_second <= 0:
        raise ValueError("Need two samples and a positive interval/tick rate")
    first, last = samples[0], samples[-1]
    if any((s["pid"], s["start_ticks"]) != (first["pid"], first["start_ticks"]) for s in samples):
        raise ValueError("Process identity changed during measurement")
    delta = last["cpu_ticks"] - first["cpu_ticks"]
    if delta < 0:
        raise ValueError("Process CPU counter decreased")
    cpu_seconds = delta / ticks_per_second
    return {"pid": first["pid"], "start_ticks": first["start_ticks"],
            "elapsed_seconds": elapsed, "samples": len(samples),
            "cpu_seconds": cpu_seconds, "cpu_percent_one_core": cpu_seconds / elapsed * 100,
            "rss_start_bytes": first["rss_bytes"], "rss_end_bytes": last["rss_bytes"],
            "rss_min_bytes": min(s["rss_bytes"] for s in samples),
            "rss_max_bytes": max(s["rss_bytes"] for s in samples)}


def arguments(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--seconds", type=float, default=60)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    if args.pid < 1 or not math.isfinite(args.seconds) or not 0 < args.seconds <= 3600:
        parser.error("PID must be positive; seconds must be finite, positive and at most 3600")
    return args


def main(argv=None):
    args = arguments(argv)
    path = Path(f"/proc/{args.pid}/stat")
    page_size = os.sysconf("SC_PAGE_SIZE")
    samples = [parse_stat(path.read_text(), page_size)]
    start = time.monotonic()
    while time.monotonic() - start < args.seconds:
        time.sleep(min(1, max(0, args.seconds - (time.monotonic() - start))))
        samples.append(parse_stat(path.read_text(), page_size))
    result = summarize(samples, time.monotonic() - start, os.sysconf("SC_CLK_TCK"))
    result["scope"] = "parent process only; uncontrolled passive sample; not FPS or per-plugin attribution"
    result["limitations"] = ["No proof of idle state", "No child-process lifetime tracing", "No frame-presentation measurement"]
    text = json.dumps(result, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text)
    print(text, end="")


if __name__ == "__main__":
    main()
