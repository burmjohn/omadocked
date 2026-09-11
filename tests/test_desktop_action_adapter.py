"""Root desktop-action policy; isolated fixture data, no native launch."""
import json
import unittest
import test_daily_adapter as daily


class DesktopActionAdapterTests(unittest.TestCase):
    def setUp(self):
        self.probe = daily.DailyAdapterTests()
        self.probe.setUp()
        self.addCleanup(self.probe.tearDown)
        self.probe.start()
        self.fixture = {"entries": [
            {"id": "fixture-a", "name": "Fixture A", "launchable": True,
             "actions": [{"id": "one", "name": "First action"}]},
            {"id": "fixture-b", "name": "Fixture B", "launchable": True,
             "actions": [{"id": "two", "name": "Second action"}]}],
            "windows": [{"key": "a", "appId": "fixture-a"}, {"key": "b", "appId": "fixture-b"}]}
        self.assertTrue(self.call("fixtureApps", json.dumps(self.fixture)))

    def call(self, method, *args):
        try:
            return self.probe.call(method, *map(str, args))
        except json.JSONDecodeError:
            self.fail("Missing typed IPC response for " + method)

    def test_explicit_exact_action_and_duplicate_protection(self):
        self.assertEqual(self.call("desktopActions", "fixture-a"), [{"id": "one", "name": "First action"}])
        self.assertEqual(self.call("desktopActions", "constructor"), [])
        self.assertFalse(self.call("desktopAction", "fixture-a", "two"))
        self.assertFalse(self.call("desktopAction", "fixture-b", "one"))
        self.assertFalse(self.call("desktopAction", "fixture-a", " one"))
        self.assertTrue(self.call("desktopAction", "fixture-a", "one"))
        self.assertFalse(self.call("desktopAction", "fixture-a", "one"))
        state = self.call("snapshot")
        self.assertTrue(next(a for a in state["apps"] if a["id"] == "fixture-a")["pending"])
        self.assertFalse(self.probe.config.exists(), "Action requests must not persist internal records")

    def test_removed_action_and_hidden_chooser_are_inert(self):
        state = self.call("snapshot")
        self.assertFalse(self.call("actionChooser", state["output"], "fixture-a"))
        self.fixture["entries"][0]["actions"] = []
        self.assertTrue(self.call("fixtureApps", json.dumps(self.fixture)))
        self.assertEqual(self.call("desktopActions", "fixture-a"), [])
        self.assertFalse(self.call("desktopAction", "fixture-a", "one"))
        self.assertFalse(self.probe.config.exists())
