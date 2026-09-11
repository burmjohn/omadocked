"""Launch a desktop ID through GLib (Exec codes, Terminal, Path); never a shell parser."""
import os
import sys
import json
import shutil
import stat
import subprocess
from pathlib import Path
from urllib.parse import urlsplit


def launch(desktop_id):
    if os.environ.get("OMADOCKED_TEST_MODE") == "1":
        raise RuntimeError("Launching is disabled in test mode")
    if (not isinstance(desktop_id, str) or not desktop_id or len(desktop_id) > 512
            or desktop_id in ("menu", ".", "..")
            or any(c in "/\\" or ord(c) < 32 for c in desktop_id)):
        raise ValueError("Invalid desktop entry ID")
    from gi.repository import GioUnix
    try:
        entry = GioUnix.DesktopAppInfo.new(desktop_id + ".desktop")
    except TypeError as exc:  # PyGObject reports a native NULL constructor as TypeError.
        raise RuntimeError("Desktop entry no longer exists or cannot be launched") from exc
    if entry is None:
        raise RuntimeError("Desktop entry no longer exists or cannot be launched")
    if not entry.launch([], None):
        raise RuntimeError("Desktop entry launch rejected")


def text(value, label, empty=True):
    if not isinstance(value, str) or "\0" in value or (not empty and not value):
        raise ValueError("Invalid " + label)
    return value


def command_argv(record):
    program = text(record.get("program", ""), "program", empty=False)
    if "/" in program and not program.startswith("/"):
        raise ValueError("Program path must be absolute")
    args = record.get("args", [])
    if not isinstance(args, list) or len(args) > 256:
        raise ValueError("Invalid argument vector")
    argv = [program, *[text(arg, "argument") for arg in args]]
    cwd = text(record.get("workingDirectory", ""), "working directory")
    if cwd and not Path(cwd).is_absolute():
        raise ValueError("Working directory must be absolute")
    terminal = record.get("terminal", False)
    if not isinstance(terminal, bool):
        raise ValueError("Invalid terminal flag")
    if terminal:
        executable = shutil.which("xdg-terminal-exec")
        if not executable:
            raise RuntimeError("Terminal launch requires xdg-terminal-exec")
        # Installed default-terminal API: --dir=DIR [--] command [arguments ...].
        argv = [executable, *(["--dir=" + cwd] if cwd else []), "--", *argv]
    return argv


def spawn(argv, cwd):
    # No shell, splitting, environment expansion, inherited input or output pipes.
    # Observe quick command failures; persistent applications are not killed.
    process = subprocess.Popen(argv, cwd=cwd or None, stdin=subprocess.DEVNULL,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               start_new_session=True)
    try:
        status = process.wait(timeout=1)
    except subprocess.TimeoutExpired:
        return
    if status:
        raise RuntimeError("Command failed with exit code " + str(status))


def folder_action(record):
    root = text(record.get("root"), "folder root", empty=False)
    target = text(record.get("target"), "folder target", empty=False)
    action = record.get("action")
    if not os.path.isabs(root) or action not in ("entry", "manager", "terminal"):
        raise ValueError("Invalid folder action")
    while len(root) > 1 and root.endswith("/"):
        root = root[:-1]
    fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        identity = os.fstat(fd)
        expected = record.get("rootIdentity")
        actual = {"device": str(identity.st_dev), "inode": str(identity.st_ino)}
        if expected is not None and expected != actual:
            raise ValueError("Folder changed; reopen its stack")
        if action == "entry":
            if expected is None or os.path.dirname(target) != root.rstrip("/") and not (root == "/" and os.path.dirname(target) == "/"):
                raise ValueError("Entry is outside the scanned folder")
            name = os.path.basename(target)
            if not name or name.startswith("."):
                raise ValueError("Invalid folder entry")
            entry = os.stat(name, dir_fd=fd, follow_symlinks=False)
            if not (stat.S_ISREG(entry.st_mode) or stat.S_ISDIR(entry.st_mode)):
                raise ValueError("Links and special files cannot be opened from the stack")
        elif target != root:
            raise ValueError("Folder target changed")
        current = os.stat(root, follow_symlinks=False)
        if (current.st_dev, current.st_ino) != (identity.st_dev, identity.st_ino):
            raise ValueError("Folder changed; reopen its stack")
        if action == "terminal":
            return spawn(["xdg-terminal-exec", "--dir=" + root], root)
        return spawn(["xdg-open", target], "")
    finally:
        os.close(fd)


def launch_record(record):
    if os.environ.get("OMADOCKED_TEST_MODE") == "1":
        raise RuntimeError("Launching is disabled in test mode")
    if not isinstance(record, dict) or record.get("enabled") is not True:
        raise ValueError("Launcher is disabled")
    kind = record.get("kind")
    if kind == "folder-action":
        return folder_action(record)
    if kind == "application":
        return launch(record.get("desktopId"))
    if kind == "desktop-action":
        desktop_id, action_id = record.get("desktopId"), record.get("actionId")
        # Settings reserves an app ID, not a desktop-entry action ID.
        if desktop_id == "menu":
            raise ValueError("Invalid desktop action identifier")
        for token in (desktop_id, action_id):
            if (not isinstance(token, str) or not token or len(token) > 512
                    or token != token.strip() or token in (".", "..")
                    or any(c in "/\\;" or ord(c) < 32 or ord(c) == 127 for c in token)):
                raise ValueError("Invalid desktop action identifier")
        from gi.repository import GioUnix
        try:
            entry = GioUnix.DesktopAppInfo.new(desktop_id + ".desktop")
        except TypeError as exc:
            raise RuntimeError("Desktop entry no longer exists or cannot be launched") from exc
        if entry is None:
            raise RuntimeError("Desktop entry no longer exists or cannot be launched")
        if entry.list_actions().count(action_id) != 1:
            raise ValueError("Desktop action no longer advertised")
        # Gio's void result means submitted, not a new window or client success.
        return entry.launch_action(action_id, None)
    if kind == "command":
        return spawn(command_argv(record), record.get("workingDirectory", ""))
    if kind == "action":
        actions = {"quick-menu": ["omarchy", "menu", "toggle", "root"],
                   "keybindings": ["omarchy", "menu", "keybindings"]}
        if record.get("action") not in actions:
            raise ValueError("Unsupported Omarchy action")
        return spawn(actions[record["action"]], "")
    target = text(record.get("target", ""), "target", empty=False)
    if kind == "link":
        uri = urlsplit(target)
        if uri.scheme.lower() not in ("http", "https") or not uri.hostname or any(c.isspace() or ord(c) < 32 for c in target):
            raise ValueError("Only absolute HTTP/HTTPS URLs are supported")
    elif kind in ("file", "folder"):
        path = Path(target)
        if not path.is_absolute():
            raise ValueError("Target path must be absolute")
        if not (path.is_file() if kind == "file" else path.is_dir()):
            raise ValueError("Target does not exist or has the wrong type")
        target = path.as_uri()
    else:
        raise ValueError("Launcher cannot be activated")
    from gi.repository import Gio
    if not Gio.AppInfo.launch_default_for_uri(target, None):
        raise RuntimeError("Default application launch rejected")


if __name__ == "__main__":
    try:
        if sys.argv[1] == "--record":
            launch_record(json.loads(sys.argv[2]))
        else:
            launch(sys.argv[1])
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
