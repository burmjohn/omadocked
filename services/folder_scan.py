#!/usr/bin/env python3
"""Bounded metadata-only directory scanner for the folder chooser."""
from __future__ import annotations

import json
import errno
import math
import multiprocessing
import os
import re
import stat
import signal
import sys
import time
from typing import Any, Callable

VERSION = 1
DEFAULT_LIMIT = 16
DEFAULT_MAX_INSPECTED = 512
MAX_INSPECTED_LIMIT = 4096
MAX_REQUEST_BYTES = 64 * 1024
_TOKEN = re.compile(r"^[A-Za-z0-9_-]{1,128}$")

_MESSAGES = {
    "missing": "Folder is no longer available.",
    "not-directory": "This location is not a folder.",
    "unreadable": "Folder cannot be read.",
    "timeout": "Folder scan timed out.",
    "cancelled": "Folder scan was cancelled.",
    "too-large": "Folder has too many items to inspect safely.",
    "changed": "Folder changed during the scan.",
}


def _leaf_path(path: str) -> str:
    if not isinstance(path, str) or not os.path.isabs(path) or "\x00" in path:
        raise ValueError("path must be an absolute filesystem path")
    while len(path) > 1 and path.endswith("/"):
        path = path[:-1]
    return path


def _validate_request(path: str, generation: int, token: str, max_inspected: int, limit: int) -> None:
    _leaf_path(path)
    if (isinstance(generation, bool) or not isinstance(generation, int)
            or not 0 <= generation <= 9_007_199_254_740_991):
        raise ValueError("generation must be a non-negative integer")
    if not isinstance(token, str) or _TOKEN.fullmatch(token) is None:
        raise ValueError("token is invalid")
    if isinstance(max_inspected, bool) or not isinstance(max_inspected, int) or not 1 <= max_inspected <= MAX_INSPECTED_LIMIT:
        raise ValueError("maxInspected is invalid")
    if isinstance(limit, bool) or not isinstance(limit, int) or limit != DEFAULT_LIMIT:
        raise ValueError("limit is invalid")


def _base(generation: int, token: str, status: str, complete: bool, inspected: int) -> dict[str, Any]:
    result: dict[str, Any] = {
        "version": VERSION,
        "generation": generation,
        "token": token,
        "status": status,
        "complete": complete,
        "inspected": inspected,
        "entries": [],
        "receipt": {
            "generation": generation,
            "token": token,
            "inspected": inspected,
            "complete": complete,
        },
    }
    if status in _MESSAGES:
        result["error"] = {"code": status, "message": _MESSAGES[status]}
    return result


def _failure(generation: int, token: str, status: str, inspected: int = 0) -> dict[str, Any]:
    return _base(generation, token, status, False, inspected)


def _relative_time(mtime_ns: int, now_ns: int) -> str:
    seconds = max(0, (now_ns - mtime_ns) // 1_000_000_000)
    if seconds < 5:
        return "just now"
    units = ((31_536_000, "year"), (2_592_000, "month"), (86_400, "day"),
             (3_600, "hour"), (60, "minute"), (1, "second"))
    for scale, word in units:
        if seconds >= scale:
            value = seconds // scale
            return f"{value} {word}{'' if value == 1 else 's'} ago"
    return "just now"


def _entry_type(mode: int) -> str:
    if stat.S_ISLNK(mode):
        return "symlink"
    if stat.S_ISDIR(mode):
        return "directory"
    if stat.S_ISREG(mode):
        return "file"
    return "other"


def _icon_category(name: str, kind: str) -> str:
    if kind == "directory":
        return "folder"
    if kind == "symlink":
        return "link"
    if kind != "file":
        return "other"
    extension = os.path.splitext(name)[1].lower()
    if extension in {".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".avif"}:
        return "image"
    if extension in {".mp3", ".ogg", ".wav", ".flac", ".m4a"}:
        return "audio"
    if extension in {".mp4", ".mkv", ".webm", ".mov", ".avi"}:
        return "video"
    if extension in {".zip", ".tar", ".gz", ".bz2", ".xz", ".7z", ".rar"}:
        return "archive"
    if extension in {".py", ".js", ".qml", ".c", ".cpp", ".h", ".rs", ".go", ".sh"}:
        return "code"
    return "document"


def scan_folder(path: str, generation: int, token: str, *,
                max_inspected: int = DEFAULT_MAX_INSPECTED,
                limit: int = DEFAULT_LIMIT,
                timeout_seconds: float = 0.25,
                now_ns: int | None = None,
                cancelled: Callable[[], bool] | None = None) -> dict[str, Any]:
    """Inspect an inode-anchored root without following root or child symlinks.

    Completed paths are valid only with the returned rootIdentity. Any later open
    must reopen the root with no-follow semantics and compare device/inode first.
    """
    _validate_request(path, generation, token, max_inspected, limit)
    path = _leaf_path(path)
    if (isinstance(timeout_seconds, bool) or not isinstance(timeout_seconds, (int, float))
            or not math.isfinite(timeout_seconds) or timeout_seconds < 0):
        raise ValueError("timeout is invalid")
    cancelled = cancelled or (lambda: False)
    started = time.monotonic()

    def interrupted() -> str | None:
        if cancelled():
            return "cancelled"
        if time.monotonic() - started >= timeout_seconds:
            return "timeout"
        return None

    stopped = interrupted()
    if stopped:
        return _failure(generation, token, stopped)

    root_fd = -1
    try:
        flags = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        root_fd = os.open(path, flags)
        root_stat = os.fstat(root_fd)
        if not stat.S_ISDIR(root_stat.st_mode):
            os.close(root_fd)
            root_fd = -1
            return _failure(generation, token, "not-directory")
        if root_stat.st_mode & (stat.S_IRUSR | stat.S_IRGRP | stat.S_IROTH) == 0:
            os.close(root_fd)
            root_fd = -1
            return _failure(generation, token, "unreadable")
    except FileNotFoundError:
        if root_fd >= 0:
            os.close(root_fd)
        return _failure(generation, token, "missing")
    except NotADirectoryError:
        if root_fd >= 0:
            os.close(root_fd)
        return _failure(generation, token, "not-directory")
    except PermissionError:
        if root_fd >= 0:
            os.close(root_fd)
        return _failure(generation, token, "unreadable")
    except OSError as error:
        if root_fd >= 0:
            os.close(root_fd)
        if error.errno in (errno.ELOOP, errno.ENOTDIR):
            return _failure(generation, token, "not-directory")
        return _failure(generation, token, "unreadable")

    inspected = 0
    rows: list[dict[str, Any]] = []
    clock_ns = time.time_ns() if now_ns is None else now_ns
    enumerated = False
    try:
        with os.scandir(root_fd) as iterator:
            while True:
                stopped = interrupted()
                if stopped:
                    return _failure(generation, token, stopped, inspected)
                try:
                    entry = next(iterator)
                except StopIteration:
                    break
                if inspected >= max_inspected:
                    result = _failure(generation, token, "too-large", inspected)
                    result["observedAtLeast"] = inspected + 1
                    return result
                inspected += 1
                if entry.name.startswith("."):
                    continue
                try:
                    metadata = entry.stat(follow_symlinks=False)
                except FileNotFoundError:
                    continue
                except PermissionError:
                    continue
                except OSError:
                    continue
                kind = _entry_type(metadata.st_mode)
                rows.append({
                    "name": entry.name,
                    "path": os.path.join(path, entry.name),
                    "type": kind,
                    "size": metadata.st_size if kind == "file" else None,
                    # Decimal text preserves nanoseconds across the QML/JSON boundary.
                    "mtimeNs": str(metadata.st_mtime_ns),
                    "relativeTime": _relative_time(metadata.st_mtime_ns, clock_ns),
                    "iconCategory": _icon_category(entry.name, kind),
                })
        enumerated = True
    except FileNotFoundError:
        return _failure(generation, token, "changed", inspected)
    except NotADirectoryError:
        return _failure(generation, token, "not-directory", inspected)
    except PermissionError:
        return _failure(generation, token, "unreadable", inspected)
    except OSError:
        return _failure(generation, token, "unreadable", inspected)
    finally:
        if not enumerated and root_fd >= 0:
            os.close(root_fd)

    try:
        current = os.stat(path, follow_symlinks=False)
    except OSError:
        os.close(root_fd)
        return _failure(generation, token, "changed", inspected)
    if (current.st_dev, current.st_ino) != (root_stat.st_dev, root_stat.st_ino):
        os.close(root_fd)
        return _failure(generation, token, "changed", inspected)
    os.close(root_fd)

    rows.sort(key=lambda row: (-int(row["mtimeNs"]), row["name"]))
    total = len(rows)
    result = _base(generation, token, "empty" if total == 0 else "ok", True, inspected)
    result["total"] = total
    result["omitted"] = max(0, total - limit)
    result["entries"] = rows[:limit]
    result["rootIdentity"] = {"device": str(root_stat.st_dev), "inode": str(root_stat.st_ino)}
    return result


def _scan_worker(connection: Any, args: tuple[Any, ...], kwargs: dict[str, Any], supervisor_pid: int) -> None:
    signal.signal(signal.SIGTERM, signal.SIG_DFL)
    # Linux ownership guarantee, independent of the QML Process destructor's
    # signal and the supervisor's finally block. SIGKILL cannot be intercepted.
    # Capture the expected parent BEFORE fork; reading it only here misses death
    # between fork and setup. Recheck AFTER prctl to close that race.
    import ctypes
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(1, signal.SIGKILL, 0, 0, 0) != 0:  # PR_SET_PDEATHSIG
        os._exit(1)  # fail closed: no filesystem work without ownership
    if os.getppid() != supervisor_pid:
        os._exit(1)
    try:
        connection.send(scan_folder(*args, **kwargs))
    except BaseException:
        connection.send(_failure(args[1], args[2], "unreadable"))
    finally:
        connection.close()


def scan_folder_hard(path: str, generation: int, token: str, *,
                     max_inspected: int = DEFAULT_MAX_INSPECTED,
                     limit: int = DEFAULT_LIMIT,
                     timeout_seconds: float = 0.25,
                     now_ns: int | None = None,
                     cancelled: Callable[[], bool] | None = None) -> dict[str, Any]:
    """Run a scan in a disposable process so blocking filesystem calls are bounded."""
    _validate_request(path, generation, token, max_inspected, limit)
    if (isinstance(timeout_seconds, bool) or not isinstance(timeout_seconds, (int, float))
            or not math.isfinite(timeout_seconds) or timeout_seconds < 0):
        raise ValueError("timeout is invalid")
    cancelled = cancelled or (lambda: False)
    if cancelled():
        return _failure(generation, token, "cancelled")
    if timeout_seconds == 0:
        return _failure(generation, token, "timeout")

    deadline = time.monotonic() + timeout_seconds
    context = multiprocessing.get_context("fork")
    receiver, sender = context.Pipe(duplex=False)
    process = context.Process(target=_scan_worker,
        args=(sender, (path, generation, token), {"max_inspected": max_inspected,
            "limit": limit, "timeout_seconds": timeout_seconds, "now_ns": now_ns}, os.getpid()))
    process.start()
    sender.close()
    status = "timeout"
    try:
        while True:
            if cancelled():
                status = "cancelled"
                break
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            if receiver.poll(min(0.01, remaining)):
                result = receiver.recv()
                process.join(0.05)
                return result
    finally:
        receiver.close()
        if process.is_alive():
            process.terminate()
            process.join(0.1)
        if process.is_alive():
            process.kill()
            process.join()
    return _failure(generation, token, status)


def _main() -> int:
    stopped = False

    def cancel(_signum, _frame):
        nonlocal stopped
        stopped = True

    signal.signal(signal.SIGTERM, cancel)
    try:
        raw = sys.stdin.buffer.read(MAX_REQUEST_BYTES + 1)
        if len(raw) > MAX_REQUEST_BYTES:
            raise ValueError("request too large")
        request = json.loads(raw.decode("utf-8"))
        if not isinstance(request, dict) or set(request) - {"path", "generation", "token", "maxInspected", "timeoutMs"}:
            raise ValueError("invalid request")
        timeout_ms = request.get("timeoutMs", 250)
        if isinstance(timeout_ms, bool) or not isinstance(timeout_ms, (int, float)) or not 0 <= timeout_ms <= 10_000:
            raise ValueError("invalid timeout")
        path = request.get("path")
        generation = request.get("generation")
        request_token = request.get("token")
        if not isinstance(path, str) or not isinstance(generation, int) or not isinstance(request_token, str):
            raise ValueError("invalid request fields")
        result = scan_folder_hard(path, generation, request_token,
                             max_inspected=request.get("maxInspected", DEFAULT_MAX_INSPECTED),
                             timeout_seconds=timeout_ms / 1000, cancelled=lambda: stopped)
        json.dump(result, sys.stdout, ensure_ascii=True, separators=(",", ":"))
        sys.stdout.write("\n")
        return 0
    except (ValueError, TypeError, UnicodeError, json.JSONDecodeError):
        sys.stderr.write("Folder scan request was rejected.\n")
        return 2


if __name__ == "__main__":
    raise SystemExit(_main())
