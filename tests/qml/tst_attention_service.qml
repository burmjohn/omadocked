import QtQuick
import QtTest
import "../../services"


TestCase {
    id: test
    name: "AttentionServiceProduction"
    SignalSpy { id: soundSpy; signalName: "soundRequested" }
    function test_soundRequiresOptInKnownDndAndEligibleEvent() {
        const host = createTemporaryObject(hostFixture, test);
        const shell = createTemporaryObject(shellFixture, test, {current:host});
        const registry = createTemporaryObject(registryFixture, test);
        const service = createService({apps:[app(false, false)], hostShell:shell, pluginRegistry:registry});
        soundSpy.target = service;
        soundSpy.clear();
        host.popupModel.append({originalId:70,timestamp:Date.now(),app:"Fixture"});
        compare(soundSpy.count, 0);
        service.urgentSound = true;
        host.popupModel.append({originalId:71,timestamp:Date.now(),app:"Fixture"});
        compare(soundSpy.count, 1);
        compare(soundSpy.signalArguments[0][0], "bell");
        host.doNotDisturb = true;
        host.popupModel.append({originalId:72,timestamp:Date.now(),app:"Fixture"});
        compare(soundSpy.count, 1);
        host.doNotDisturb = false;
        service.apps = [app(false, true)];
        host.popupModel.append({originalId:73,timestamp:Date.now(),app:"Fixture"});
        compare(soundSpy.count, 1);
        soundSpy.target = null;
    }
    Component {
        id: actionFixture
        QtObject { signal urgentAcknowledged(string appId, string key) }
    }
    function test_verifiedActionAcknowledgesOnlyExactNativeWindow() {
        const source = createTemporaryObject(actionFixture, test);
        const service = createService({apps:[app(false, false)]});
        verify(service.actionSource !== undefined, "controller acknowledgement contract required");
        service.actionSource = source;
        const two = app(false, false);
        two.windows.push({id:"other", focused:false, openedAtMs:1, urgent:false});
        service.apps = [two];
        const urgent = JSON.parse(JSON.stringify(two));
        urgent.windows.forEach(w => w.urgent = true);
        service.apps = [urgent];
        compare(service.hints.length, 1);
        verify(typeof service.urgentKey === "function");
        compare(service.urgentKey("fixture.app"), "fixture.window");
        compare(service.urgentKey("wrong-app"), "");
        source.urgentAcknowledged("wrong-app", "fixture.window");
        compare(Object.keys(service._state.attention["fixture.app"].windows).length, 2);
        source.urgentAcknowledged("fixture.app", "fixture.window");
        compare(Object.keys(service._state.attention["fixture.app"].windows).join(), "other");
        source.urgentAcknowledged("fixture.app", "other");
        compare(service.hints.length, 0);
    }
    function app(urgent, focused) {
        return {id:"fixture.app", notificationIds:["Fixture"], pwaIds:[], browserIds:[],
            focused:!!focused, launchPending:false, openedAtMs:1,
            windows:[{id:"fixture.window", focused:!!focused, openedAtMs:1, urgent:urgent}]};
    }
    function createService(properties) {
        const component = Qt.createComponent("../../services/AttentionService.qml");
        compare(component.status, Component.Ready, component.errorString());
        return createTemporaryObject(component, test, properties || {});
    }
    Component {
        id: hostFixture
        QtObject {
            property var popupModel: rows
            property bool doNotDisturb: false
            property bool settingsLoaded: true
            property ListModel rows: ListModel {}
            function isRestoredRow(row) { return row.originalId === 9; }
        }
    }
    Component {
        id: shellFixture
        QtObject {
            property var current: null
            property string requested: ""
            function serviceFor(id) { requested = id; return id === "fixture.clone" ? current : null; }
        }
    }
    Component {
        id: registryFixture
        QtObject { function resolveEnabledId(id) { return "fixture.clone"; } }
    }
    function test_notificationsCloneBaselineDndAndReplacement() {
        const host = createTemporaryObject(hostFixture, test);
        host.popupModel.append({originalId:1, timestamp:Date.now(), app:"Fixture", body:"PRIVATE FIXTURE"});
        const shell = createTemporaryObject(shellFixture, test, {current:host});
        const registry = createTemporaryObject(registryFixture, test);
        const service = createService({apps:[app(false, false)], hostShell:shell, pluginRegistry:registry});
        compare(shell.requested, "fixture.clone");
        compare(service.notificationStatus, "available");
        compare(service.hints, []);
        host.popupModel.append({originalId:9, timestamp:Date.now(), app:"Fixture", body:"RESTORED FIXTURE"});
        compare(service.hints, []);
        host.popupModel.append({originalId:2, timestamp:Date.now(), app:"Fixture", body:"PRIVATE FIXTURE"});
        compare(service.hints, ["fixture.app"]);
        verify(JSON.stringify(service._state).indexOf("PRIVATE") < 0);
        service.apps = [app(false, true)];
        service.apps = [app(false, false)];
        host.doNotDisturb = true;
        host.popupModel.append({originalId:3, timestamp:Date.now(), app:"Fixture", body:"PRIVATE FIXTURE"});
        compare(service.hints, []);
        host.doNotDisturb = false;
        compare(service.hints, []);
        shell.current = null;
        compare(service.notificationStatus, "unavailable");
        shell.current = host;
        compare(service.hints, [], "reattachment establishes a new baseline");
        host.popupModel.append({originalId:4, timestamp:Date.now(), app:"Fixture", body:"PRIVATE FIXTURE"});
        compare(service.hints, ["fixture.app"]);
    }
    function test_disabledAndStartupRowsNeverReplay() {
        const host = createTemporaryObject(hostFixture, test);
        const now = Date.now();
        const oldRow = {originalId:42, timestamp:now, app:"Fixture"};
        host.popupModel.append(oldRow);
        const shell = createTemporaryObject(shellFixture, test, {current:host});
        const registry = createTemporaryObject(registryFixture, test);
        const service = createService({apps:[app(false, false)], hostShell:shell, pluginRegistry:registry});
        host.popupModel.clear();
        host.popupModel.append(oldRow);
        compare(service.hints, [], "existing baseline identity cannot replay, including same millisecond");
        service.enabled = false;
        host.popupModel.append({originalId:43,timestamp:Date.now(),app:"Fixture"});
        service.apps = [app(true, false)];
        service.enabled = true;
        compare(service.hints, []);
        host.popupModel.append({originalId:44,timestamp:Date.now(),app:"Fixture"});
        compare(service.hints, ["fixture.app"], "unlock/enable must not break future events");
    }
    function test_readinessUnknownAliasesAndDestroyedSubscription() {
        const host = createTemporaryObject(hostFixture, test, {settingsLoaded:false});
        const shell = createTemporaryObject(shellFixture, test, {current:host});
        const registry = createTemporaryObject(registryFixture, test);
        const service = createService({apps:[app(false, false)], hostShell:shell, pluginRegistry:registry});
        compare(service.notificationStatus, "unavailable");
        host.popupModel.append({originalId:60,timestamp:Date.now(),app:"Fixture"});
        host.settingsLoaded = true;
        compare(service.hints, []);
        host.popupModel.append({originalId:61,timestamp:Date.now(),app:"Unknown"});
        compare(service.hints, []);
        const duplicate = app(false, false);
        duplicate.id = "other";
        duplicate.windows[0].id = "other.window";
        service.apps = [app(false, false), duplicate];
        host.popupModel.append({originalId:62,timestamp:Date.now(),app:"Fixture"});
        compare(service.hints, [], "ambiguous name never chooses the first app");
        service.apps = [app(false, false)];
        service.urgentOnNotification = false;
        host.popupModel.append({originalId:63,timestamp:Date.now(),app:"Fixture"});
        service.urgentOnNotification = true;
        compare(service.hints, []);
        shell.current = createTemporaryObject(hostFixture, test);
        host.popupModel.append({originalId:64,timestamp:Date.now(),app:"Fixture"});
        compare(service.hints, [], "old service is disconnected");
        service.destroy();
        wait(0);
        shell.current.popupModel.append({originalId:65,timestamp:Date.now(),app:"Fixture"});
    }
    function test_nativeEdgesAndFocus() {
        const service = createService({apps:[app(true, false)]});
        compare(service.hints, [], "startup urgency is baseline, not a new event");
        service.apps = [app(false, false)];
        service.apps = [app(true, false)];
        compare(service.hints, ["fixture.app"]);
        service.apps = [app(true, true)];
        compare(service.hints, []);
        service.apps = [app(true, false)];
        compare(service.hints, [], "focus acknowledgement must not replay urgency");
    }
}
