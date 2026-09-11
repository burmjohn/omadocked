"""Long-lived, helper-owned configuration transaction service.

The process owns the flock and performs every persistent file operation. Its
stdout is a private JSON-lines protocol consumed by QML; errors never include
configuration paths or bytes.
"""
import fcntl
import json
import os
from pathlib import Path
import secrets
import stat
import sys


def valid_path(value):
    if not value or not value.startswith("/") or "\x00" in value:
        return False
    parts = value.split("/")
    return bool(parts[-1] and not any(part in (".", "..") for part in parts))


def emit(value):
    sys.stdout.write(json.dumps(value, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def safe_regular(info, private=False):
    return (stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid()
            and info.st_nlink == 1 and (not private or not info.st_mode & 0o077))


def open_parent(path):
    parts = path.split("/")[1:-1]
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        for part in parts:
            try:
                child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW, dir_fd=fd)
            except FileNotFoundError:
                os.mkdir(part, 0o700, dir_fd=fd)
                # Persist the newly created ancestor entry, not just the final
                # config directory. Otherwise main fsync cannot guarantee reachability.
                os.fsync(fd)
                child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW, dir_fd=fd)
            info = os.fstat(child)
            writable = info.st_mode & 0o022
            sticky_root = info.st_uid == 0 and bool(info.st_mode & stat.S_ISVTX)
            if info.st_uid not in (0, os.getuid()) or (writable and not sticky_root):
                os.close(child)
                raise ValueError("unsafe")
            os.close(fd)
            fd = child
        return fd
    except BaseException:
        os.close(fd)
        raise


class Store:
    def __init__(self, path):
        if not valid_path(path):
            raise ValueError("unsafe")
        self.path = path
        self._outcome = "no-commit"
        self._main_durable = False
        self._unresolved = False
        self._stage = "idle"
        self.name = path.rsplit("/", 1)[1]
        self.directory = open_parent(path)
        try:
            self.lock = os.open(self.name + ".lock", os.O_RDWR | os.O_CREAT | os.O_CLOEXEC
                                | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600, dir_fd=self.directory)
            info = os.fstat(self.lock)
            if not safe_regular(info, private=True):
                raise ValueError("unsafe")
            fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            current = os.stat(self.name + ".lock", dir_fd=self.directory, follow_symlinks=False)
            if (current.st_dev, current.st_ino) != (info.st_dev, info.st_ino):
                raise ValueError("unsafe")
        except BaseException:
            os.close(self.directory)
            raise

    def close(self):
        os.close(self.lock)
        os.close(self.directory)

    def read(self, name=None, durable=False):
        target = name or self.name
        try:
            fd = os.open(target, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=self.directory)
        except FileNotFoundError:
            return "", True
        try:
            info = os.fstat(fd)
            if not safe_regular(info):
                raise ValueError("unsafe")
            chunks = []
            while True:
                data = os.read(fd, 65536)
                if not data:
                    break
                chunks.append(data)
                if sum(map(len, chunks)) > 4 * 1024 * 1024:
                    raise ValueError("unsafe")
            if durable:
                os.fsync(fd)
            return b"".join(chunks).decode("utf-8"), False
        finally:
            os.close(fd)

    def atomic_write(self, name, text):
        if not isinstance(text, str) or len(text.encode("utf-8")) > 4 * 1024 * 1024:
            raise ValueError("unsafe")
        # Refuse special or multiply-linked existing targets before replacement.
        try:
            existing = os.stat(name, dir_fd=self.directory, follow_symlinks=False)
            if not safe_regular(existing) or not existing.st_mode & stat.S_IWUSR:
                raise ValueError("unsafe")
        except FileNotFoundError:
            pass
        temporary = ".omadocked-" + secrets.token_hex(16)
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC
                     | os.O_NOFOLLOW, 0o600, dir_fd=self.directory)
        try:
            data = text.encode("utf-8")
            offset = 0
            while offset < len(data):
                offset += os.write(fd, data[offset:])
            os.fsync(fd)
            os.close(fd)
            fd = -1
            # Once rename is attempted, an interrupted/lost result cannot prove
            # no commit. Readable bytes alone cannot establish directory durability.
            if name == self.name:
                self._outcome = "indeterminate"
                self._stage = "main-rename"
            os.replace(temporary, name, src_dir_fd=self.directory, dst_dir_fd=self.directory)
            if name == self.name:
                self._stage = "main-directory-fsync"
            os.fsync(self.directory)
            if name == self.name:
                self._main_durable = True
                self._stage = "main-readback"
        finally:
            if fd >= 0:
                os.close(fd)
            try:
                os.unlink(temporary, dir_fd=self.directory)
            except FileNotFoundError:
                pass
        actual, missing = self.read(name)
        if missing or actual != text:
            raise OSError("readback")
        if name == self.name:
            self._outcome = "durable"

    def ready(self):
        # A new owner reconciles CURRENT bytes after a lost/indeterminate receipt.
        # This barrier establishes durability now, never retroactively attributes
        # success to the previous transaction. No main or backup bytes are written.
        text, missing = self.read(durable=True)
        os.fsync(self.directory)
        if self.read() != (text, missing):
            raise OSError("reconciliation-readback")
        backup, _ = self.read(self.name + ".lkg")
        return {"type": "ready", "ok": True, "missing": missing, "text": text, "backup": backup}

    def conflict(self, request):
        text, missing = self.read()
        if request.get("expected") != text or bool(request.get("missing")) != missing:
            return {"id": request.get("id"), "ok": False, "error": "conflict"}
        return None

    def commit(self, request):
        conflict = self.conflict(request)
        if conflict:
            return conflict
        replacement = request.get("replacement")
        fallback = request.get("fallback")
        if not isinstance(replacement, str) or not isinstance(fallback, str):
            raise ValueError("protocol")
        before = fallback if request.get("missing") else request.get("expected")
        self.atomic_write(self.name + ".lkg", before)
        self.atomic_write(self.name, replacement)
        try:
            self.atomic_write(self.name + ".lkg", replacement)
        except (OSError, UnicodeError, ValueError):
            # Main is durable and verified; backup refresh is a separate outcome.
            return {"id": request.get("id"), "ok": True, "committed": True, "outcome": "durable",
                    "backupDegraded": True}
        return {"id": request.get("id"), "ok": True, "committed": True, "outcome": "durable",
                "backupDegraded": False}

    def recover(self, request):
        text, missing = self.read()
        backup, backup_missing = self.read(self.name + ".lkg")
        if (missing or request.get("expected") != text or backup_missing
                or request.get("backup") != backup):
            return {"id": request.get("id"), "ok": False, "error": "conflict"}
        for _ in range(32):
            damaged_name = self.name + ".damaged-" + secrets.token_hex(12)
            try:
                os.stat(damaged_name, dir_fd=self.directory, follow_symlinks=False)
            except FileNotFoundError:
                self.atomic_write(damaged_name, text)
                break
        else:
            raise OSError("preserve")
        self.atomic_write(self.name, backup)
        try:
            self.atomic_write(self.name + ".lkg", backup)
        except (OSError, UnicodeError, ValueError):
            return {"id": request.get("id"), "ok": True, "committed": True, "outcome": "durable",
                    "backupDegraded": True}
        return {"id": request.get("id"), "ok": True, "committed": True, "outcome": "durable",
                "backupDegraded": False}

    def request(self, request):
        if not isinstance(request, dict) or not isinstance(request.get("id"), int):
            raise ValueError("protocol")
        if self._unresolved:
            return {"id": request["id"], "ok": False, "error": "unresolved",
                    "outcome": "indeterminate"}
        self._outcome = "no-commit"
        self._main_durable = False
        self._stage = "pre-main"
        try:
            if request.get("op") == "commit":
                result = self.commit(request)
            elif request.get("op") == "recover":
                result = self.recover(request)
            else:
                result = {"id": request["id"], "ok": False, "error": "unsupported"}
            result.setdefault("outcome", "no-commit")
            return result
        except (OSError, UnicodeError, ValueError, TypeError):
            self._unresolved = self._outcome == "indeterminate"
            result = {"id": request["id"], "ok": False, "error": "storage",
                      "outcome": self._outcome, "stage": self._stage,
                      "mainDurable": self._main_durable}
            if self._unresolved:
                # Observation only: never upgrade failed fsync to durable success.
                try:
                    actual, missing = self.read()
                    replacement = request.get("backup") if request.get("op") == "recover" else request.get("replacement")
                    result["mainMatchesReplacement"] = not missing and actual == replacement
                except (OSError, UnicodeError, ValueError):
                    result["mainMatchesReplacement"] = None
            return result


def main(argv):
    if len(argv) != 2:
        emit({"type": "ready", "ok": False, "error": "unsafe"})
        return 2
    try:
        store = Store(argv[1])
    except BlockingIOError:
        emit({"type": "ready", "ok": False, "error": "busy"})
        return 3
    except (OSError, UnicodeError, ValueError):
        emit({"type": "ready", "ok": False, "error": "unsafe"})
        return 2
    try:
        try:
            ready = store.ready()
        except (OSError, UnicodeError, ValueError):
            emit({"type": "ready", "ok": False, "error": "reconciliation"})
            return 2
        emit(ready)
        for line in sys.stdin:
            request = None
            try:
                request = json.loads(line)
                result = store.request(request)
            except (OSError, UnicodeError, ValueError, TypeError):
                request_id = request.get("id") if isinstance(request, dict) else None
                result = {"id": request_id, "ok": False, "error": "protocol", "outcome": "no-commit"}
            # Delivery loss must not turn a durable result into a failure receipt.
            # The controller owns the indeterminate outcome if no receipt arrives.
            emit(result)
    finally:
        store.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
