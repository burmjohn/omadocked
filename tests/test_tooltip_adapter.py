"""Hidden production Settings -> controller -> durable writer roundtrip."""
import json
import time
import unittest
import test_daily_adapter as daily


class TooltipAdapterTests(unittest.TestCase):
    start = daily.DailyAdapterTests.start
    stop = daily.DailyAdapterTests.stop
    call = daily.DailyAdapterTests.call
    tearDown = daily.DailyAdapterTests.tearDown

    def setUp(self):
        daily.DailyAdapterTests.setUp(self)
        surface = self.directory / "DockSurface.qml"
        text = surface.read_text()
        at = text.rfind("}")
        surface.write_text(text[:at] + '''
    function fixtureNames(value: bool): void { view.showAppNamesRequested(value); }
    function fixtureNamesState(): var {
        return {value:view.showAppNames,managed:view.settingsManaged,keyboard:view.wantsKeyboard,
                tooltip:view.tooltipIndex,popupWidth:view.popupRect.width};
    }
''' + text[at:])
        shell = self.directory / "shell.qml"
        shell.write_text(shell.read_text().replace('target: "omadocked-prototype"', '''target: "omadocked-prototype"
        function fixtureNames(value: bool): void { dock.representative().fixtureNames(value); }
        function fixtureNamesState(): string { return JSON.stringify(dock.representative().fixtureNamesState()); }
'''))

    def test_native_settings_signal_commit_restart_and_failed_write(self):
        self.start()
        initial = self.call("fixtureNamesState")
        self.assertTrue(initial["value"])
        self.assertTrue(initial["managed"])
        self.call("fixtureNames", "false")
        deadline = time.monotonic() + 5
        while self.call("fixtureNamesState")["value"] and time.monotonic() < deadline:
            time.sleep(.02)
        self.assertFalse(self.call("fixtureNamesState")["value"])
        self.assertFalse(json.loads(self.config.read_text())["settings"]["showAppNames"])
        self.stop()
        self.start()
        self.assertFalse(self.call("fixtureNamesState")["value"])
        self.config.chmod(0o444)
        self.call("fixtureNames", "true")
        time.sleep(.2)
        state = self.call("fixtureNamesState")
        self.assertFalse(state["value"])
        self.assertFalse(state["keyboard"])
        self.assertEqual(state["popupWidth"], 0)
        self.assertEqual(state["tooltip"], -1)
        self.assertFalse(json.loads(self.config.read_text())["settings"]["showAppNames"])
