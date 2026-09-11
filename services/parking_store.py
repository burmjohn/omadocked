#!/usr/bin/python3
"""Serialized, journaled Hyprland parking operations.

The helper is the only journal writer and executes argv directly. Receipts expose
session keys and states, never titles or compositor inventory.
"""
import fcntl
import json
import os
from pathlib import Path
import re
import secrets
import stat
import subprocess
import sys

PARKING_WORKSPACE = "special:Omadocked"
MAX_BYTES = 1024 * 1024
ADDRESS = re.compile(r"0x[0-9a-fA-F]+\Z")


def emit(value):
    sys.stdout.write(json.dumps(value, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def valid_path(value):
    return (isinstance(value, str) and value.startswith("/") and "\x00" not in value
            and bool(value.rsplit("/", 1)[-1])
            and not any(part in (".", "..") for part in value.split("/")))


def safe_token(value, limit=512):
    return isinstance(value, str) and 0 < len(value) <= limit and not any(ord(c) < 32 for c in value)


def safe_regular(info, private=False):
    return (stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid() and info.st_nlink == 1
            and (not private or not info.st_mode & 0o077))


def open_parent(path):
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        for part in path.split("/")[1:-1]:
            try:
                child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW,
                                dir_fd=fd)
            except FileNotFoundError:
                os.mkdir(part, 0o700, dir_fd=fd)
                child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW,
                                dir_fd=fd)
            info = os.fstat(child)
            sticky_root = info.st_uid == 0 and bool(info.st_mode & stat.S_ISVTX)
            if info.st_uid not in (0, os.getuid()) or (info.st_mode & 0o022 and not sticky_root):
                os.close(child)
                raise ValueError("unsafe")
            os.close(fd)
            fd = child
        return fd
    except BaseException:
        os.close(fd)
        raise


class Journal:
    def __init__(self, path, session):
        if not valid_path(path) or not safe_token(session, 256):
            raise ValueError("unsafe")
        self.path = path
        self.name = path.rsplit("/", 1)[1]
        self.session = session
        self.directory = open_parent(path)
        try:
            self.lock = os.open(self.name + ".lock", os.O_RDWR | os.O_CREAT | os.O_CLOEXEC
                                | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600, dir_fd=self.directory)
            if not safe_regular(os.fstat(self.lock), private=True):
                raise ValueError("unsafe")
            fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            current = os.stat(self.name + ".lock", dir_fd=self.directory, follow_symlinks=False)
            info = os.fstat(self.lock)
            if (current.st_dev, current.st_ino) != (info.st_dev, info.st_ino):
                raise ValueError("unsafe")
        except BaseException:
            os.close(self.directory)
            raise
        self.data, self.missing = self.read()

    def close(self):
        os.close(self.lock)
        os.close(self.directory)

    def read(self):
        try:
            fd = os.open(self.name, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=self.directory)
        except FileNotFoundError:
            return {"version": 1, "session": self.session, "nextSequence": 1, "records": []}, True
        try:
            info = os.fstat(fd)
            if not safe_regular(info, private=True) or info.st_size > MAX_BYTES:
                raise ValueError("unsafe")
            raw = b""
            while True:
                chunk = os.read(fd, 65536)
                if not chunk:
                    break
                raw += chunk
                if len(raw) > MAX_BYTES:
                    raise ValueError("unsafe")
            value = json.loads(raw.decode())
            self.validate(value)
            return value, False
        finally:
            os.close(fd)

    @staticmethod
    def validate(value):
        if (not isinstance(value, dict) or set(value) != {"version", "session", "nextSequence", "records"}
                or value["version"] != 1 or not safe_token(value["session"], 256)
                or not isinstance(value["nextSequence"], int) or value["nextSequence"] < 1
                or not isinstance(value["records"], list) or len(value["records"]) > 1024):
            raise ValueError("unsafe")
        keys = []
        for record in value["records"]:
            if not valid_record(record):
                raise ValueError("unsafe")
            keys.append(record["identity"]["key"])
        if len(set(keys)) != len(keys):
            raise ValueError("unsafe")

    def write(self):
        self.validate(self.data)
        text = json.dumps(self.data, separators=(",", ":")) + "\n"
        temporary = ".omadocked-parking-" + secrets.token_hex(16)
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW,
                     0o600, dir_fd=self.directory)
        try:
            raw = text.encode()
            offset = 0
            while offset < len(raw):
                offset += os.write(fd, raw[offset:])
            os.fsync(fd)
            os.close(fd)
            fd = -1
            os.replace(temporary, self.name, src_dir_fd=self.directory, dst_dir_fd=self.directory)
            os.fsync(self.directory)
        finally:
            if fd >= 0:
                os.close(fd)
            try:
                os.unlink(temporary, dir_fd=self.directory)
            except FileNotFoundError:
                pass
        actual, missing = self.read()
        if missing or actual != self.data:
            raise OSError("readback")
        self.missing = False


def valid_identity(value):
    return (isinstance(value, dict) and set(value) in ({"key", "address", "pid", "class", "initialClass", "xwayland"},
            {"key", "address", "pid", "class", "initialClass", "xwayland", "stableId"})
            and ("stableId" not in value or valid_stable_id(value["stableId"]))
            and safe_token(value["key"]) and bool(ADDRESS.fullmatch(value["address"]))
            and isinstance(value["pid"], int) and value["pid"] > 0
            and safe_token(value["class"]) and safe_token(value["initialClass"])
            and isinstance(value["xwayland"], bool))


def valid_origin(value):
    return (isinstance(value, dict) and set(value) == {"workspace", "monitor", "floating", "at", "size"}
            and safe_token(value["workspace"], 256) and not value["workspace"].startswith("special:")
            and isinstance(value["monitor"], int) and isinstance(value["floating"], bool)
            and isinstance(value["at"], list) and len(value["at"]) == 2 and all(isinstance(v, int) for v in value["at"])
            and isinstance(value["size"], list) and len(value["size"]) == 2 and all(isinstance(v, int) and v >= 0 for v in value["size"]))


def valid_record(value):
    return (isinstance(value, dict) and set(value) == {"identity", "origin", "state", "sequence"}
            and valid_identity(value["identity"]) and valid_origin(value["origin"])
            and value["state"] in ("parking", "parked", "restoring")
            and isinstance(value["sequence"], int) and value["sequence"] >= 1)


def valid_stable_id(value):
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{1,16}", value) is not None


def client_identity(client, identity):
    return (valid_stable_id(identity.get("stableId")) and client.get("stableId") == identity["stableId"]
            and client.get("address") == identity["address"] and client.get("pid") == identity["pid"]
            and client.get("class") == identity["class"]
            and client.get("initialClass") == identity["initialClass"]
            and client.get("xwayland") is identity["xwayland"])


class Parking:
    def __init__(self, journal, executable):
        self.journal = journal
        self.executable = executable
        self.blocked = []
        self.reconcile()
        self.startup_recovery_required = bool(self.journal.data["records"])

    def query(self, kind):
        result = subprocess.run([self.executable, "-j", kind], capture_output=True, text=True,
                                timeout=3, check=True)
        value = json.loads(result.stdout)
        if kind == "clients" and not isinstance(value, list):
            raise ValueError("protocol")
        return value

    def clients(self):
        return self.query("clients")

    @staticmethod
    def find(clients, address):
        rows = [row for row in clients if row.get("address") == address]
        return rows[0] if len(rows) == 1 else None

    def move(self, identity, destination):
        if not valid_stable_id(identity.get("stableId")):
            raise ValueError("identity-unavailable")
        # json.dumps creates Lua-compatible quoted scalar strings. No shell exists.
        code = ("hl.dispatch(hl.dsp.window.move({window=" + json.dumps("address:" + identity["address"])
                + ",workspace=" + json.dumps(destination, ensure_ascii=False) + ",follow=false}))")
        # Check generation inside the same compositor evaluation as the dispatch.
        # Both APIs are present in Hyprland v0.56.2; absent APIs fail without moving.
        code = ("for _,w in ipairs(hl.get_windows()) do if w.address == '" + identity["address"]
                + "' and type(w.stable_id) == 'number' and string.format('%x',w.stable_id) == '" + identity["stableId"]
                + "' then " + code + "; break end end")
        subprocess.run([self.executable, "eval", code], capture_output=True, text=True,
                       timeout=3, check=True)

    def persist(self):
        self.journal.write()

    def reconcile(self):
        self.blocked = []
        records = self.journal.data["records"]
        if self.journal.data["session"] != self.journal.session:
            if not records:
                # Empty leftover journals are from a previous login with nothing
                # parked. Adopt the live compositor session before any mutation.
                self.journal.data["session"] = self.journal.session
                self.persist()
                return
            self.blocked = [r["identity"]["key"] for r in records]
            return
        clients = self.clients()
        retained = []
        changed = False
        for record in records:
            identity = record["identity"]
            client = self.find(clients, identity["address"])
            if client is None:
                changed = True  # independently verified external close
                continue
            if not client_identity(client, identity):
                retained.append(record)
                self.blocked.append(identity["key"])
                continue
            workspace = (client.get("workspace") or {}).get("name", "")
            if workspace == PARKING_WORKSPACE:
                if record["state"] != "parked":
                    record["state"] = "parked"
                    changed = True
                retained.append(record)
            else:
                # Exact surviving identity is independently verified outside parking:
                # either the pre-move request never happened or recovery completed.
                changed = True
        if changed:
            self.journal.data["records"] = retained
            self.persist()
        if not self.journal.data["records"]:
            self.startup_recovery_required = False

    def response(self, request, ok, status, key=None, **extra):
        value = {"id": request.get("id"), "ok": ok, "status": status}
        if key is not None:
            value["key"] = key
        value.update(extra)
        return value

    def record_for(self, key):
        return next((r for r in self.journal.data["records"] if r["identity"]["key"] == key), None)

    def park(self, request):
        identity, origin = request.get("window"), request.get("origin")
        key = identity.get("key") if isinstance(identity, dict) else None
        if (self.blocked or self.startup_recovery_required
                or self.journal.data["session"] != self.journal.session):
            return self.response(request, False, "recovery-required", key)
        if not valid_identity(identity) or not valid_origin(origin) or self.record_for(identity["key"]):
            return self.response(request, False, "invalid", key)
        if not valid_stable_id(identity.get("stableId")):
            return self.response(request, False, "identity-unavailable", key)
        clients = self.clients()
        client = self.find(clients, identity["address"])
        if not client or not client_identity(client, identity):
            return self.response(request, False, "identity-mismatch", key)
        if (client.get("workspace") or {}).get("name") != origin["workspace"]:
            return self.response(request, False, "origin-changed", key)
        sequence = self.journal.data["nextSequence"]
        self.journal.data["nextSequence"] += 1
        record = {"identity": identity, "origin": origin, "state": "parking", "sequence": sequence}
        self.journal.data["records"].append(record)
        self.persist()  # durable and read back before dispatch
        try:
            self.move(identity, PARKING_WORKSPACE)
            after = self.find(self.clients(), identity["address"])
            if not after or not client_identity(after, identity) or (after.get("workspace") or {}).get("name") != PARKING_WORKSPACE:
                return self.response(request, False, "unverified", key)
            record["state"] = "parked"
            self.persist()
            return self.response(request, True, "parked", key)
        except (OSError, subprocess.SubprocessError, ValueError, json.JSONDecodeError):
            return self.response(request, False, "unverified", key)

    def destination(self, record, mode):
        if mode == "here":
            active = self.query("activeworkspace")
            target = active.get("name") if isinstance(active, dict) else ""
            return target if safe_token(target, 256) and not target.startswith("special:") else None
        if mode == "origin":
            target = record["origin"]["workspace"]
            workspaces = self.query("workspaces")
            return target if isinstance(workspaces, list) and any(w.get("name") == target for w in workspaces) else None
        return None

    def restore_record(self, request, record, mode):
        identity = record["identity"]
        key = identity["key"]
        if key in self.blocked:
            return self.response(request, False, "identity-mismatch", key)
        client = self.find(self.clients(), identity["address"])
        if not client or not client_identity(client, identity):
            return self.response(request, False, "identity-mismatch", key)
        if (client.get("workspace") or {}).get("name") != PARKING_WORKSPACE:
            return self.response(request, False, "not-parked", key)
        destination = self.destination(record, mode)
        if destination is None:
            status = "origin-unavailable" if mode == "origin" else "current-workspace-unavailable"
            return self.response(request, False, status, key)
        record["state"] = "restoring"
        self.persist()
        try:
            self.move(identity, destination)
            after = self.find(self.clients(), identity["address"])
            if not after or not client_identity(after, identity) or (after.get("workspace") or {}).get("name") != destination:
                return self.response(request, False, "unverified", key)
            self.journal.data["records"].remove(record)
            self.persist()
            if not self.journal.data["records"]:
                self.startup_recovery_required = False
            return self.response(request, True, "restored", key, workspace=destination)
        except (OSError, subprocess.SubprocessError, ValueError, json.JSONDecodeError):
            return self.response(request, False, "unverified", key)

    def restore(self, request):
        key, mode = request.get("key"), request.get("mode")
        if not safe_token(key) or mode not in ("here", "origin"):
            return self.response(request, False, "invalid", key if isinstance(key, str) else None)
        record = self.record_for(key)
        if not record:
            return self.response(request, False, "missing", key)
        return self.restore_record(request, record, mode)

    def restore_fifo(self, request):
        if request.get("mode") not in ("here", "origin"):
            return self.response(request, False, "invalid")
        # request() freshly reconciles identities/workspaces before selection;
        # restore_record() independently rechecks the selected survivor again.
        # Blocked records remain intact and visible, but cannot starve survivors.
        blocked = list(self.blocked)
        records = [r for r in self.journal.data["records"]
                   if r["state"] == "parked" and r["identity"]["key"] not in blocked]
        if not records:
            return self.response(request, False, "blocked" if blocked else "empty", blocked=blocked)
        result = self.restore_record(request, min(records, key=lambda r: r["sequence"]), request["mode"])
        result["blocked"] = blocked
        return result

    def recover(self, request):
        mode = request.get("mode")
        if mode not in ("here", "origin"):
            return self.response(request, False, "invalid")
        if self.journal.data["session"] != self.journal.session:
            return self.response(request, False, "blocked", blocked=list(self.blocked), restored=[])
        restored, blocked = [], []
        records = sorted(list(self.journal.data["records"]), key=lambda r: r["sequence"])
        for record in records:
            result = self.restore_record(request, record, mode)
            (restored if result["ok"] else blocked).append(record["identity"]["key"])
        status = "restored" if restored and not blocked else "partial" if restored else "blocked" if blocked else "empty"
        if not self.journal.data["records"]:
            self.startup_recovery_required = False
        return self.response(request, bool(restored) and not blocked, status, restored=restored, blocked=blocked)

    def request(self, request):
        if not isinstance(request, dict) or not isinstance(request.get("id"), int):
            raise ValueError("protocol")
        operation = request.get("op")
        if operation in ("status", "park", "restore", "restore-fifo", "recover"):
            self.reconcile()
        if operation == "park":
            return self.park(request)
        if operation == "restore":
            return self.restore(request)
        if operation == "restore-fifo":
            return self.restore_fifo(request)
        if operation == "recover":
            return self.recover(request)
        if operation == "status":
            records = sorted(self.journal.data["records"], key=lambda r: r["sequence"])
            return {"id": request["id"], "ok": True, "status": "ready",
                    "keys": [r["identity"]["key"] for r in records],
                    "records": [{"key": r["identity"]["key"], "state": r["state"], "sequence": r["sequence"],
                                 "identity": {k: r["identity"][k] for k in r["identity"] if k != "key"}}
                                for r in records], "blocked": list(self.blocked),
                    "recoveryRequired": self.startup_recovery_required}
        return self.response(request, False, "unsupported")


def main(argv):
    if len(argv) != 2:
        emit({"type": "ready", "ok": False, "error": "unsafe"})
        return 2
    session = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    executable = (os.environ.get("OMADOCKED_HYPRCTL", "/usr/bin/hyprctl")
                  if os.environ.get("OMADOCKED_TEST_MODE") == "1" else "/usr/bin/hyprctl")
    if not (os.path.isabs(executable) and safe_token(executable, 4096)):
        emit({"type": "ready", "ok": False, "error": "unsafe"})
        return 2
    try:
        journal = Journal(argv[1], session)
        parking = Parking(journal, executable)
    except BlockingIOError:
        emit({"type": "ready", "ok": False, "error": "busy"})
        return 3
    except (OSError, UnicodeError, ValueError, json.JSONDecodeError, subprocess.SubprocessError):
        emit({"type": "ready", "ok": False, "error": "unsafe"})
        return 2
    try:
        emit({"type": "ready", "ok": True,
              "pending": len(journal.data["records"]) - len(parking.blocked), "blocked": len(parking.blocked)})
        for line in sys.stdin:
            request = None
            try:
                request = json.loads(line)
                emit(parking.request(request))
            except (OSError, UnicodeError, ValueError, TypeError, json.JSONDecodeError, subprocess.SubprocessError):
                request_id = request.get("id") if isinstance(request, dict) else None
                emit({"id": request_id, "ok": False, "status": "error"})
    finally:
        journal.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
