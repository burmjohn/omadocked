import QtQuick
import QtTest
import "../../core/AppLogic.js" as Apps
import "../../core/DockLogic.js" as Dock

TestCase {
    name: "ModelWorkload"
    property var entries: []
    property var windows: []
    property var scales: []
    property var result
    function initTestCase() {
        for (let i = 0; i < 500; ++i)
            entries.push({id: "app-" + i, name: "Fixture " + i, startupClass: "Class-" + i,
                          icon: "application-x-executable", launchable: true});
        for (let i = 0; i < 50; ++i)
            windows.push({key: "w-" + i, appId: "Class-" + i, active: i === 0});
        for (let i = 0; i < 32; ++i) scales.push(1);
    }
    function benchmark_model500Entries50Windows() {
        result = Apps.build(entries, windows, ["app-499"], []);
    }
    function benchmark_wave32Icons() {
        for (let i = 0; i < 32; ++i)
            scales[i] = Dock.scaleAt(i, 640, 0, 48, "wave", false, false);
        result = Dock.layout(scales, 800, 44, 4);
    }
    function cleanupTestCase() { verify(result !== undefined); }
}
