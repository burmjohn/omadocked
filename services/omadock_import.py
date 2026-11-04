"""Preview-first Omadock → Omadocked import. Preview never writes or executes."""
import hashlib
import json
import os
from pathlib import Path
from services.config_store import Store


UNSUPPORTED_KEYS = {
    "iconSize": lambda v: v in (0, "auto"),
    "showAppsButton": lambda v: True,
    "showMinimizedTiles": lambda v: True,
}

SETTING_MAP = {
    "iconSize": "iconSize",
    "autohide": "autoHide",
    "intelligentAutohide": "intelligentHide",
    "minimizeMode": "minimizeMode",
    "hoverEffect": "motionMode",
    "advancedTooltips": "advancedTooltips",
    "launchBounce": "launchBounce",
    "showUrgentHint": "showUrgentHint",
    "urgentOnNotification": "urgentOnNotification",
    "urgentSound": "urgentSound",
    "urgentSoundName": "urgentSoundName",
    "folderColor": "folderColor",
    "revealDelay": "revealDelay",
    "tooltipDelay": "tooltipDelay",
    "showTooltips": "showAppNames",
    "itemSpacing": "itemSpacing",
    "bgColor": "backgroundColor",
}

SOUND_NAMES = ("bell", "message-new-instant", "complete", "dialog-information",
               "dialog-warning", "phone-incoming-call", "alarm-clock-elapsed", "none")
FOLDER_COLORS = ("theme", "symbolic", "white", "black", "Yaru-sage", "Yaru-olive",
                 "Yaru-blue", "Yaru-purple", "Yaru-magenta", "Yaru-red", "Yaru-yellow",
                 "Yaru-wartybrown", "Yaru-prussiangreen", "Yaru-dark")
BOOLEAN_SETTINGS = {
    "autoHide", "intelligentHide", "advancedTooltips", "launchBounce", "showUrgentHint",
    "urgentOnNotification", "urgentSound", "showAppNames", "themeOpacity", "reducedMotion",
    "reserveSpace", "followActiveOutput", "previewsEnabled", "livePreviews", "showAppsButton",
}


def _valid_setting(key, value):
    if key == "iconSize":
        return isinstance(value, int) and not isinstance(value, bool) and (value == 0 or 28 <= value <= 72)
    if key == "zoomSize":
        return isinstance(value, int) and not isinstance(value, bool) and 100 <= value <= 200
    if key == "waveWidth":
        return isinstance(value, int) and not isinstance(value, bool) and 10 <= value <= 50 and value % 5 == 0
    if key == "transparency":
        return isinstance(value, int) and not isinstance(value, bool) and 0 <= value <= 100
    if key == "tooltipDelay":
        return isinstance(value, int) and not isinstance(value, bool) and 0 <= value <= 5000
    if key == "revealDelay":
        return isinstance(value, int) and not isinstance(value, bool) and 0 <= value <= 2000
    if key == "shape":
        return value in ("rounded", "round", "square", "theme")
    if key == "itemSpacing":
        return value in (2, 4, 8)
    if key == "backgroundColor":
        return isinstance(value, str) and (value in ("theme", "none") or (
            len(value) == 7 and value.startswith("#") and all(c in "0123456789abcdefABCDEF" for c in value[1:])))
    if key == "motionMode":
        return value in ("wave", "zoom", "off")
    if key == "minimizeMode":
        return value in ("active", "all", "off")
    if key == "folderColor":
        return value in FOLDER_COLORS
    if key == "urgentSoundName":
        return value in SOUND_NAMES
    if key == "monitorMode":
        return value in ("all", "selected")
    if key == "selectedOutputs":
        return (isinstance(value, list) and len(value) <= 64
                and all(isinstance(n, str) and n.strip() and len(n) <= 256 and n not in value[:i]
                        and all(ord(c) >= 32 for c in n) for i, n in enumerate(value)))
    if key in BOOLEAN_SETTINGS:
        return isinstance(value, bool)
    return False


def _printable(value, limit=8192):
    return isinstance(value, str) and len(value) <= limit and all(ord(c) >= 32 for c in value)


def _strip_desktop(value):
    text = str(value or "").strip()
    if not text.endswith(".desktop"):
        return text
    stem = text[:-8]
    if "." not in stem or stem.endswith(".desktop"):
        return stem
    return text


def _pins(dock_path):
    if dock_path is None or not Path(dock_path).is_file():
        return []
    text = Path(dock_path).read_text()
    parsed = json.loads(text) if text.strip() else {}
    raw = parsed.get("pinned") if isinstance(parsed, dict) else []
    pins = []
    seen = set()
    if isinstance(raw, list):
        for item in raw:
            ident = _strip_desktop(item)
            if (not ident or ident in seen or ident in (".", "..", "menu", "omarchy-menu") or ident.startswith("launcher:")
                    or len(ident) > 512 or "/" in ident or "\\" in ident
                    or any(ord(c) < 32 for c in ident)):
                continue
            seen.add(ident)
            pins.append(ident)
    return pins


def _launcher_id(target):
    digest = hashlib.sha1(target.encode("utf-8")).hexdigest()
    return "launcher:%s-%s-4%s-8%s-%s" % (digest[:8], digest[8:12], digest[13:16], digest[17:20], digest[20:32])


def _folders(raw):
    launchers = []
    seen = set()
    if not isinstance(raw, list):
        return launchers
    for folder in raw:
        if not isinstance(folder, dict):
            continue
        path = os.path.expanduser(str(folder.get("path") or ""))
        name = str(folder.get("name") or "")
        icon = str(folder.get("icon") or "folder")
        if (not path.startswith("/") or ".." in path.split("/") or not name or path in seen
                or not _printable(name) or not _printable(icon) or not _printable(path)):
            continue
        seen.add(path)
        launchers.append({
            "id": _launcher_id(path),
            "kind": "folder",
            "name": name,
            "icon": icon,
            "desktopId": "",
            "program": "",
            "args": [],
            "workingDirectory": "",
            "terminal": False,
            "target": path,
            "action": "",
            "enabled": True,
        })
    return launchers


def _shape(value):
    if value == "pill":
        return "round"
    if value == "auto":
        return "theme"
    return value


def preview(dock_path, settings_path):
    result = {"applied": False, "pins": _pins(dock_path), "settings": {}, "launchers": [], "unsupported": []}
    if settings_path is None or not Path(settings_path).is_file():
        return result
    raw = json.loads(Path(settings_path).read_text() or "{}")
    if not isinstance(raw, dict):
        return result
    known = set(SETTING_MAP) | {"opacity", "shape", "iconSize", "showAppsButton", "showMinimizedTiles",
                                 "pinnedFolders", "screen", "themeOpacity"}
    for key, value in raw.items():
        if key == "pinnedFolders":
            result["launchers"] = _folders(value)
            continue
        if key in UNSUPPORTED_KEYS and UNSUPPORTED_KEYS[key](value):
            result["unsupported"].append(key)
            continue
        if key == "opacity":
            if value in ("theme", "auto", -1):
                result["settings"]["themeOpacity"] = True
            elif isinstance(value, (int, float)):
                result["settings"]["transparency"] = max(0, min(100, round((1 - float(value)) * 100)))
            else:
                result["unsupported"].append(key)
            continue
        if key == "shape":
            result["settings"]["shape"] = _shape(value)
            continue
        if key == "screen" and isinstance(value, str) and value:
            result["settings"]["monitorMode"] = "selected"
            result["settings"]["selectedOutputs"] = [value]
            continue
        if key in SETTING_MAP:
            mapped = SETTING_MAP[key]
            if not _valid_setting(mapped, value):
                result["unsupported"].append(key)
                continue
            result["settings"][mapped] = value
            continue
        if key not in known:
            result["unsupported"].append(key)
    return result


def _config(preview_data):
    settings = {
        "iconSize": 44, "transparency": 0, "shape": "rounded", "itemSpacing": 4,
        "backgroundColor": "theme", "themeOpacity": False, "zoomSize": 145, "waveWidth": 25,
        "motionMode": "wave", "reducedMotion": False, "showAppNames": True, "advancedTooltips": False,
        "launchBounce": True, "tooltipDelay": 450, "revealDelay": 160, "autoHide": True,
        "intelligentHide": False, "minimizeMode": "active", "reserveSpace": False,
        "followActiveOutput": False, "monitorMode": "all", "selectedOutputs": [],
        "folderColor": "theme", "previewsEnabled": True, "livePreviews": False,
        "showUrgentHint": True, "urgentOnNotification": True, "urgentSound": False,
        "urgentSoundName": "bell", "showAppsButton": True,
    }
    settings.update({k: v for k, v in (preview_data.get("settings") or {}).items() if _valid_setting(k, v)})
    if settings.get("iconSize") in (0, "auto") or not isinstance(settings.get("iconSize"), int):
        settings["iconSize"] = 44
    if settings.get("monitorMode") == "selected" and not settings.get("selectedOutputs"):
        settings["monitorMode"] = "all"
        settings["selectedOutputs"] = []
    return {
        "version": 2,
        "pins": preview_data.get("pins") or [],
        "launchers": preview_data.get("launchers") or [],
        "settings": settings,
        "overrides": {},
    }


def _valid_pin(ident):
    return (_printable(ident, 512) and ident and ident not in (".", "..", "menu", "omarchy-menu")
            and not ident.startswith("launcher:") and "/" not in ident and "\\" not in ident)


def _valid_launcher(record):
    if not isinstance(record, dict):
        return False
    allowed = {"id", "kind", "name", "icon", "desktopId", "program", "args",
               "workingDirectory", "terminal", "target", "action", "enabled"}
    if set(record) - allowed:
        return False
    for key in ("id", "kind", "name", "icon", "desktopId", "program", "workingDirectory", "target", "action"):
        if not _printable(record.get(key, "")):
            return False
    ident = record.get("id")
    kind = record.get("kind")
    name = record.get("name")
    if not ident.startswith("launcher:"):
        return False
    body = ident[9:]
    if len(body) != 36 or body[8] != "-" or body[13] != "-" or body[18] != "-" or body[23] != "-":
        return False
    if body[14] != "4" or body[19] not in "89ab":
        return False
    if any(c not in "0123456789abcdef-" for c in body):
        return False
    if kind not in ("application", "command", "link", "file", "folder", "action", "separator"):
        return False
    if kind != "separator" and not name:
        return False
    if kind in ("file", "folder") and not str(record.get("target") or "").startswith("/"):
        return False
    if not isinstance(record.get("terminal"), bool) or not isinstance(record.get("enabled"), bool):
        return False
    args = record.get("args")
    if not isinstance(args, list) or len(args) > 256:
        return False
    if any(not isinstance(a, str) or len(a) > 32768 or "\0" in a for a in args):
        return False
    working = record.get("workingDirectory") or ""
    if working and not working.startswith("/"):
        return False
    return True


def _validate_destination(config):
    if not isinstance(config, dict) or config.get("version") != 2:
        raise ValueError("invalid destination")
    allowed = {"version", "pins", "launchers", "settings", "overrides"}
    if set(config) - allowed:
        raise ValueError("invalid destination field")
    pins = config.get("pins")
    if not isinstance(pins, list) or len(pins) > 256 or any(not _valid_pin(p) for p in pins):
        raise ValueError("invalid destination pins")
    if len(pins) != len(set(pins)):
        raise ValueError("invalid destination pins")
    launchers = config.get("launchers")
    if not isinstance(launchers, list) or len(launchers) > 256 or any(not _valid_launcher(r) for r in launchers):
        raise ValueError("invalid destination launchers")
    ids = [r["id"] for r in launchers]
    if len(ids) != len(set(ids)):
        raise ValueError("invalid destination launchers")
    overrides = config.get("overrides")
    if not isinstance(overrides, dict) or len(overrides) > 256:
        raise ValueError("invalid destination overrides")
    settings = config.get("settings")
    if not isinstance(settings, dict) or any(not _valid_setting(k, v) for k, v in settings.items()):
        raise ValueError("invalid destination settings")
    if settings.get("monitorMode") == "selected" and not settings.get("selectedOutputs"):
        raise ValueError("invalid destination settings")


def apply(dock_path, settings_path, dest_path):
    sources = [Path(p) for p in (dock_path, settings_path) if p is not None]
    if not sources or any(not p.is_file() for p in sources):
        raise ValueError("missing import source")
    for source in sources:
        if not isinstance(json.loads(source.read_text()), dict):
            raise ValueError("invalid import source: expected an object")
    dest = Path(dest_path).absolute()
    if not dest.is_file() or dest.is_symlink() or ".." in dest.parts:
        raise ValueError("unsafe destination")
    preview_data = preview(dock_path, settings_path)
    payload_config = _config(preview_data)
    _validate_destination(payload_config)
    payload = json.dumps(payload_config, indent=2) + "\n"
    try:
        store = Store(str(dest))
    except BlockingIOError:
        return {"applied": False, "error": "busy", "outcome": "no-commit"}
    try:
        ready = store.ready()
        if ready["missing"]:
            raise ValueError("unsafe destination")
        backup_name = store.name + ".import-bak"
        try:
            os.stat(backup_name, dir_fd=store.directory, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            raise ValueError("import backup already exists; archive it before another import")
        # Preserve the exact pre-import bytes under the same lease, with the
        # Store's ownership checks, atomic replacement, fsync and readback.
        store.atomic_write(backup_name, ready["text"])
        receipt = store.request({
            "id": 1, "op": "commit", "expected": ready["text"],
            "missing": False, "replacement": payload, "fallback": "",
        })
        return dict(receipt, applied=bool(receipt.get("ok") and receipt.get("committed")
                                         and receipt.get("outcome") == "durable"),
                    backup=str(dest.with_name(backup_name)), pins=preview_data["pins"],
                    unsupported=preview_data["unsupported"])
    finally:
        store.close()
