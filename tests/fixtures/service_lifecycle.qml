import QtQuick
import Quickshell
import "../../services" as Services

ShellRoot {
    Services.AppService { id: service }
    Services.AppService { id: readonlyService }
    Services.AppService { id: invalidSnapshotService }
    function verify(value, message) { if (!value) throw new Error(message); }
    Timer {
        interval: 100
        running: true
        onTriggered: {
            try {
                verify(service.testMode && service.configPath === "" && service.ready, "isolated fixture");
                service._parkingActive = {id:42, publicId:42, op:"park", request:{op:"park"}};
                service._parkingLost("helper-timeout");
                verify(service.lastParkingReceipt.transactionId === 42 && !service.lastParkingReceipt.ok
                    && service.lastParkingReceipt.status === "helper-timeout-unresolved", "lost dispatched operation is unresolved");
                service._parkingMessage(JSON.stringify({type:"ready", ok:true}));
                verify(service._parkingActive === null, "late ready reopened lost owner");
                service._parkingMessage(JSON.stringify({id:service._parkingSerial, ok:true, records:[]}));
                verify(!service.parkingReady, "late status reopened lost owner");
                const revision = service.parkingRevision;
                service._parkingLost("helper-stopped");
                verify(service.parkingRevision === revision, "duplicate terminal receipt");
                verify(service.configure({minimizeMode:"off"}) > 0, "off policy accepted");
                service.fixtureSet([{id:"editor", name:"Editor", launchable:true}],
                    [{key:"one", appId:"editor", active:true}, {key:"two", appId:"editor", active:false}]);
                const second = service._windows[1].key;
                verify(service.activate("editor"), "off-mode click accepted");
                verify(service._windows.find(w => w.key === second).active, "off mode must cycle without parking");
                verify(service.settings.minimizeMode === "off", "off preference preserved");
                service._ready = false;
                service._storeMessage(JSON.stringify({type:"ready", ok:false, error:"busy"}));
                verify(!service.ready, "busy without validated snapshot must not expose defaults");
                verify(!service._leaseOwned && service._leaseDead && !service.canRecover, "busy owner read only");
                readonlyService._ready = false;
                const saved = Object.assign({}, service._config, {pins:["editor"]});
                readonlyService._storeMessage(JSON.stringify({type:"ready", ok:false, error:"busy",
                    snapshot:true, text:JSON.stringify(saved), missing:false}));
                verify(readonlyService.ready && readonlyService._pins[0] === "editor", "safe snapshot loads saved pins");
                verify(readonlyService.settings.minimizeMode === "off", "safe snapshot preserves off");
                verify(!readonlyService._leaseOwned && readonlyService._leaseDead && !readonlyService.canRecover,
                    "snapshot does not grant writer ownership");
                invalidSnapshotService._ready = false;
                invalidSnapshotService._storeMessage(JSON.stringify({type:"ready", ok:false, error:"busy",
                    snapshot:true, text:"not json", missing:false}));
                verify(!invalidSnapshotService.ready, "invalid snapshot must not expose defaults");
                console.log("SERVICE_LIFECYCLE_PASS");
            } catch (error) { console.log("SERVICE_LIFECYCLE_FAIL " + error.message); }
            Qt.quit();
        }
    }
}
