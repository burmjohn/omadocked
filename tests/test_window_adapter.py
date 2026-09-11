"""Root window API contract: isolated fixtures, no user window actions or titles."""
import json
import unittest
import test_daily_adapter as daily


class WindowAdapterTests(unittest.TestCase):
    def setUp(self):
        self.probe = daily.DailyAdapterTests()
        self.probe.setUp()
        self.addCleanup(self.probe.tearDown)
        self.probe.start()
        self.fixture = {
            "entries": [{"id": i, "name": i, "icon": "application-x-executable", "launchable": True}
                        for i in ("fixture-a", "fixture-b")],
            "windows": [{"key": "a1", "appId": "fixture-a", "active": True, "title": "PRIVATE_WINDOW_TITLE_A"},
                        {"key": "a2", "appId": "fixture-a", "active": False, "title": "PRIVATE_WINDOW_TITLE_B"},
                        {"key": "b1", "appId": "fixture-b", "active": False, "title": "PRIVATE_WINDOW_TITLE_C"}]}
        self.assertTrue(self.call("fixtureApps", json.dumps(self.fixture)))

    def call(self, method, *args):
        try:
            return self.probe.call(method, *map(str, args))
        except json.JSONDecodeError:
            self.fail("Missing typed JSON IPC response for " + method)

    def test_targeted_window_actions_are_scoped_and_title_free(self):
        rows = self.call("windows", "fixture-a")
        self.assertEqual(len(rows), 2)
        first, second = [row["key"] for row in rows]
        foreign = self.call("windows", "fixture-b")[0]["key"]
        self.assertEqual(rows, [{"key": first, "active": True}, {"key": second, "active": False}])
        self.assertFalse(self.call("activateWindow", "fixture-a", foreign))
        self.assertTrue(self.call("activateWindow", "fixture-a", second))
        self.assertEqual([r["key"] for r in self.call("windows", "fixture-a") if r["active"]], [second])
        self.assertTrue(self.call("cycleWindows", "fixture-a", -1))
        self.assertEqual([r["key"] for r in self.call("windows", "fixture-a") if r["active"]], [first])
        self.assertFalse(self.call("closeWindow", "fixture-a", foreign))
        self.assertTrue(self.call("closeWindow", "fixture-a", first))
        self.assertEqual([r["key"] for r in self.call("windows", "fixture-a")], [second])
        self.assertEqual([r["key"] for r in self.call("windows", "fixture-b")], [foreign])
        self.assertFalse(self.call("activateWindow", "fixture-a", first))
        self.assertFalse(self.call("closeWindow", "fixture-a", first))
        self.assertNotIn("PRIVATE_WINDOW_TITLE", json.dumps(self.call("snapshot")))
        self.assertFalse(self.probe.config.exists(), "Window actions must not write configuration")

    def test_invalid_cycle_and_unknown_group_are_inert(self):
        before = self.call("windows", "fixture-a")
        for value in (0, 2, -2, 0.5):
            self.assertFalse(self.call("cycleWindows", "fixture-a", value))
        self.assertFalse(self.call("cycleWindows", "missing", 1))
        self.assertEqual(self.call("windows", "constructor"), [])
        self.assertEqual(self.call("windows", "missing"), [])
        self.assertEqual(self.call("windows", "fixture-a"), before)
        self.assertFalse(self.call("windowChooser", self.call("snapshot")["output"], "fixture-a"),
                         "Hidden surfaces must not acquire popup focus")
