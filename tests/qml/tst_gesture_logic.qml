import QtQuick
import QtTest
import "../../core/GestureLogic.js" as Gestures

TestCase {
    name: "GestureLogic"

    readonly property var windowFixtures: [
        {key: "0xAa", mapped: true, hidden: false, parked: false},
        {key: "0xBb", mapped: true, hidden: false, parked: false},
        {key: "0xCc", mapped: true, hidden: false, parked: false}
    ]

    function test_wheelSelectionWrapsByExactStableKey_data() {
        return [
            {tag: "down-next", selected: "0xAa", delta: -120, expected: "0xBb"},
            {tag: "down-wrap", selected: "0xCc", delta: -1, expected: "0xAa"},
            {tag: "up-previous", selected: "0xCc", delta: 120, expected: "0xBb"},
            {tag: "up-wrap", selected: "0xAa", delta: 1, expected: "0xCc"},
            {tag: "unknown-starts-deterministically", selected: "0xaa", delta: -120, expected: "0xAa"}
        ];
    }

    function test_wheelSelectionWrapsByExactStableKey(data) {
        const decision = Gestures.wheelSelection(windowFixtures, data.selected, data.delta);
        compare(decision.action, "select");
        compare(decision.key, data.expected);
    }

    function test_appWheelUsesSingletonAndAllParkedFallbacks_data() {
        return [
            {tag: "singleton", windows: [{key:"only", mapped:true, hidden:false, parked:false}], reason:"singleton", key:"only"},
            {tag: "all-parked", windows: [{key:"p1", mapped:false, hidden:true, parked:true}, {key:"p2", mapped:false, hidden:true, parked:true}], reason:"all-parked", key:""}
        ];
    }

    function test_appWheelUsesSingletonAndAllParkedFallbacks(data) {
        const decision = Gestures.appWheelDecision(data.windows, "", -120);
        compare(decision.action, "cycle-app");
        compare(decision.reason, data.reason);
        compare(decision.key, data.key);
        compare(Gestures.appWheelDecision([], "", -120).action, "none");
    }

    function test_buttonPoliciesArePureAndExplicit_data() {
        return [
            {tag:"app-middle", actual:Gestures.appGesture("middle"), action:"launch-new-instance", target:""},
            {tag:"logo-left", actual:Gestures.settingsLogoGesture("left", 0), action:"quick-menu", target:""},
            {tag:"logo-right", actual:Gestures.settingsLogoGesture("right", 0), action:"settings", target:""},
            {tag:"logo-middle", actual:Gestures.settingsLogoGesture("middle", 0), action:"terminal", target:""},
            {tag:"logo-wheel-down", actual:Gestures.settingsLogoGesture("wheel", -120), action:"workspace", target:"e+1"},
            {tag:"logo-wheel-up", actual:Gestures.settingsLogoGesture("wheel", 120), action:"workspace", target:"e-1"},
            {tag:"empty-right", actual:Gestures.emptySpaceGesture("right"), action:"settings", target:""}
        ];
    }

    function test_buttonPoliciesArePureAndExplicit(data) {
        compare(data.actual.action, data.action);
        compare(data.actual.target || "", data.target);
    }

    function test_selectionRequiresMatchingSafeIntegerRevisions() {
        const malformed = [undefined, null, "8", {}, 1.5, -1, Number.MAX_SAFE_INTEGER + 1];
        malformed.forEach(function(revision) {
            compare(Gestures.acceptSelection(windowFixtures, "0xAa", revision, revision).reason, "invalid-revision");
        });
    }

    function test_appWheelValidatesDeltaBeforeEveryFallbackBranch() {
        const singleton = [{key:"only", mapped:true, hidden:false, parked:false}];
        const parked = [{key:"parked", mapped:false, hidden:true, parked:true}];
        const invalid = [0, undefined, "-120", NaN, Infinity, -Infinity];
        invalid.forEach(function(delta) {
            compare(Gestures.appWheelDecision(singleton, "", delta).reason, "invalid-wheel");
            compare(Gestures.appWheelDecision(parked, "", delta).reason, "invalid-wheel");
            compare(Gestures.appWheelDecision([], "", delta).reason, "invalid-wheel");
        });
    }

    function test_staleRevisionAndMissingExactKeyAreRejected() {
        compare(Gestures.acceptSelection(windowFixtures, "0xAa", 7, 8).reason, "stale-model");
        compare(Gestures.acceptSelection(windowFixtures, "0xaa", 8, 8).reason, "missing-key");
        const accepted = Gestures.acceptSelection(windowFixtures, "0xAa", 8, 8);
        compare(accepted.action, "activate-window");
        compare(accepted.key, "0xAa");
    }

    function test_overlapUsesOnlyMappedVisibleSelectedOutputAndWorkspace_data() {
        const dock = {x:100, y:90, width:100, height:20};
        return [
            {tag:"strict-overlap", dock:dock, windows:[{key:"a", mapped:true, hidden:false, output:"DP-1", workspace:"3", x:150, y:80, width:20, height:20}], expected:true},
            {tag:"touching-edge-is-not-overlap", dock:dock, windows:[{key:"a", mapped:true, hidden:false, output:"DP-1", workspace:"3", x:0, y:90, width:100, height:20}], expected:false},
            {tag:"unmapped-ignored", dock:dock, windows:[{key:"a", mapped:false, hidden:false, output:"DP-1", workspace:"3", x:150, y:80, width:20, height:20}], expected:false},
            {tag:"hidden-ignored", dock:dock, windows:[{key:"a", mapped:true, hidden:true, output:"DP-1", workspace:"3", x:150, y:80, width:20, height:20}], expected:false},
            {tag:"other-output-ignored", dock:dock, windows:[{key:"a", mapped:true, hidden:false, output:"HDMI-A-1", workspace:"3", x:150, y:80, width:20, height:20}], expected:false},
            {tag:"other-workspace-ignored", dock:dock, windows:[{key:"a", mapped:true, hidden:false, output:"DP-1", workspace:"4", x:150, y:80, width:20, height:20}], expected:false}
        ];
    }

    function test_overlapUsesOnlyMappedVisibleSelectedOutputAndWorkspace(data) {
        compare(Gestures.hasStrictOverlap(data.windows, data.dock, "DP-1", "3"), data.expected);
    }
}
