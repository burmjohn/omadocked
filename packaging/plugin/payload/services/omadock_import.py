"""Preview-first Omadock → Omadocked import. Preview never writes or executes."""
import hashlib
import json
import os
from pathlib import Path
import uuid


UNSUPPORTED_KEYS = {
    "iconSize": lambda v: v in (0, "auto"),
    "showAppsButton": lambda v: True,
    "showMinimizedTiles": lambda v: True,
}

SETTING_MAP = {
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
            if not ident or ident in seen or ident in (".", "..", "menu") or "/" in ident or "\\" in ident:
                continue
            seen.add(ident)
            pins.append(ident)
    return pins


def _launcher_id(target):
    digest = hashlib.sha1(target.encode("utf-8")).hexdigest()
    return "launcher:%s-%s-4%s-8%s-%s" % (digest[:8], digest[8:12], digest[13:16], digest[17:20], digest[20:32])


def _folders(raw):
    launchers = []
    if not isinstance(raw, list):
        return launchers
    for folder in raw:
        if not isinstance(folder, dict):
            continue
        path = os.path.expanduser(str(folder.get("path") or ""))
        name = str(folder.get("name") or "")
        icon = str(folder.get("icon") or "folder")
        if not path.startswith("/") or ".." in path.split("/") or not name:
            continue
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
        "urgentSoundName": "bell",
    }
    settings.update(preview_data.get("settings") or {})
    if settings.get("iconSize") in (0, "auto") or not isinstance(settings.get("iconSize"), int):
        settings["iconSize"] = 44
    return {
        "version": 2,
        "pins": preview_data.get("pins") or [],
        "launchers": preview_data.get("launchers") or [],
        "settings": settings,
        "overrides": {},
    }


def apply(dock_path, settings_path, dest_path):
    dest = Path(dest_path)
    if not dest.is_file() or dest.is_symlink() or ".." in dest.parts:
        raise ValueError("unsafe destination")
    preview_data = preview(dock_path, settings_path)
    backup = dest.with_name(dest.name + ".import-bak")
    backup.write_bytes(dest.read_bytes())
    os.chmod(backup, 0o600)
    payload = json.dumps(_config(preview_data), indent=2) + "\n"
    tmp = dest.with_name(".omadocked-import-" + uuid.uuid4().hex)
    tmp.write_text(payload)
    os.chmod(tmp, 0o600)
    os.replace(tmp, dest)
    return {"applied": True, "backup": str(backup), "pins": preview_data["pins"],
            "unsupported": preview_data["unsupported"]}
