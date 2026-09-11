import QtQuick
import QtTest
import "../../core/DockLogic.js" as Logic

TestCase {
    name: "OutputPolicy"
    function test_initialMonitorEnvironmentFailsClosed() {
        verify(typeof Logic.initialMonitorPolicy === "function", "explicit environment policy parser exists");
        compare(Logic.initialMonitorPolicy(""), {mode: "all", names: []});
        compare(Logic.initialMonitorPolicy("all"), {mode: "all", names: []});
        compare(Logic.initialMonitorPolicy("left,right,left"), {mode: "selected", names: ["left", "right"]});
        for (const raw of ["left,,right", ",", " "]) {
            const policy = Logic.initialMonitorPolicy(raw);
            compare(policy.mode, "selected");
            compare(policy.names, []);
            verify(policy.error.indexOf("OMADOCKED_SCREENS") >= 0);
            compare(Logic.activeOutputs(["left", "right"], policy.mode, policy.names), []);
        }
    }
    function test_validatePolicy() {
        verify(typeof Logic.monitorPolicy === "function", "validated monitor policy exists");
        compare(Logic.monitorPolicy("all", "[]"), {mode: "all", names: []});
        compare(Logic.monitorPolicy("selected", '["right","right","offline"]'), {mode: "selected", names: ["right", "offline"]});
        for (const entry of [["bad", "[]"], ["selected", "[]"], ["all", "{}"], ["all", "null"], ["selected", '[""]'], ["selected", '["   "]'], ["selected", '[12]'], ["selected", "bad"]])
            compare(Logic.monitorPolicy(entry[0], entry[1]), null);
    }
    function test_selectedOutputsRememberDisconnectedNames() {
        const selected = ["right", "offline"];
        compare(Logic.activeOutputs(["left", "right"], "selected", selected), ["right"]);
        compare(Logic.activeOutputs(["left", "new"], "selected", selected), []);
        compare(Logic.activeOutputs([], "selected", selected), []);
        compare(Logic.activeOutputs(["offline", "right", "new"], "selected", selected), ["offline", "right"]);
        compare(selected, ["right", "offline"]);
    }
    function test_allOutputsIncludesNewScreens() {
        verify(typeof Logic.activeOutputs === "function", "multi-output policy exists");
        compare(Logic.activeOutputs(["left", "right"], "all", []), ["left", "right"]);
        compare(Logic.activeOutputs(["left", "right", "new"], "all", []), ["left", "right", "new"]);
        compare(Logic.activeOutputs([], "all", []), []);
    }
    function test_selectedOutputRemovalAndStickyFallback() {
        verify(typeof Logic.resolveOutput === "function", "output resolver exists");
        compare(Logic.resolveOutput(["left", "right"], "right", "").name, "right");
        const removed = Logic.resolveOutput(["left"], "right", "right");
        compare(removed.name, "left");
        compare(removed.fallback, true);
        compare(removed.reason, "requested-output-unavailable");
        const empty = Logic.resolveOutput([], "right", "left");
        compare(empty.name, "");
        compare(empty.reason, "no-outputs");
        const initial = Logic.resolveOutput(["left", "right"], "", "");
        compare(initial.name, "left");
        compare(initial.fallback, true);
        compare(Logic.resolveOutput(["right", "left"], "", initial.name).name, "left");
        compare(Logic.resolveOutput(["left", "right"], "right", "left").fallback, false);
    }
}
