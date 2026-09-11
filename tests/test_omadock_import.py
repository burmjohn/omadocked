"""P4-05: preview-first Omadock import never writes or executes on preview."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load_importer():
    path = ROOT / "services" / "omadock_import.py"
    spec = importlib.util.spec_from_file_location("omadock_import", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PreviewImportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="omadocked-import-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.dock = self.root / "dock.json"
        self.dest = self.root / "pins.json"
        self.dest.write_text("untouched\n")
        self.dest.chmod(0o600)

    def test_preview_maps_pins_without_writing_or_executing(self):
        self.dock.write_text(json.dumps({"pinned": ["brave-browser.desktop", "org.telegram.desktop"]}))
        importer = load_importer()
        with patch("subprocess.Popen") as popen, patch("os.execvpe") as execvpe:
            preview = importer.preview(self.dock, None)
        self.assertFalse(preview["applied"])
        self.assertEqual(preview["pins"], ["brave-browser", "org.telegram.desktop"])
        self.assertEqual(self.dest.read_text(), "untouched\n")
        popen.assert_not_called()
        execvpe.assert_not_called()

    def test_preview_maps_settings_and_reports_unsupported_without_writing(self):
        settings = self.root / "omadock.json"
        settings.write_text(json.dumps({
            "autohide": False,
            "intelligentAutohide": True,
            "minimizeMode": "off",
            "opacity": 0.54,
            "hoverEffect": "wave",
            "shape": "pill",
            "iconSize": 0,
            "showAppsButton": False,
            "showMinimizedTiles": True,
            "pinnedFolders": [{"path": "~/Downloads", "name": "Downloads", "icon": "folder-download"}],
            "mystery": "nope",
        }))
        self.dock.write_text("{}\n")
        importer = load_importer()
        preview = importer.preview(self.dock, settings)
        self.assertFalse(preview["applied"])
        mapped = preview["settings"]
        self.assertEqual(mapped["autoHide"], False)
        self.assertEqual(mapped["intelligentHide"], True)
        self.assertEqual(mapped["minimizeMode"], "off")
        self.assertEqual(mapped["transparency"], 46)
        self.assertEqual(mapped["motionMode"], "wave")
        self.assertEqual(mapped["shape"], "round")
        self.assertIn("iconSize", preview["unsupported"])
        self.assertIn("showAppsButton", preview["unsupported"])
        self.assertIn("showMinimizedTiles", preview["unsupported"])
        self.assertIn("mystery", preview["unsupported"])
        self.assertEqual(len(preview["launchers"]), 1)
        self.assertEqual(preview["launchers"][0]["kind"], "folder")
        self.assertEqual(preview["launchers"][0]["name"], "Downloads")
        self.assertTrue(preview["launchers"][0]["target"].startswith("/"))
        self.assertEqual(self.dest.read_text(), "untouched\n")

    def test_apply_backs_up_destination_then_writes_without_executing(self):
        self.dock.write_text(json.dumps({"pinned": ["signal"]}))
        (self.root / "omadock.json").write_text(json.dumps({"minimizeMode": "off", "autohide": True}))
        importer = load_importer()
        with patch("subprocess.Popen") as popen, patch("os.execvpe") as execvpe:
            result = importer.apply(self.dock, self.root / "omadock.json", self.dest)
        self.assertTrue(result["applied"])
        backup = Path(result["backup"])
        self.assertEqual(backup.read_text(), "untouched\n")
        written = json.loads(self.dest.read_text())
        self.assertEqual(written["version"], 2)
        self.assertEqual(written["pins"], ["signal"])
        self.assertEqual(written["settings"]["minimizeMode"], "off")
        popen.assert_not_called()
        execvpe.assert_not_called()
