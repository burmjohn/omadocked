"""QML parking controller contract using only a private fake hyprctl."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest
import spawn_safety as safety

ROOT = Path(__file__).resolve().parents[1]
SHELL = '''import QtQuick
import Quickshell
import Quickshell.Io
import "services"
ShellRoot {
    AppService { id: apps }
    property var acknowledgements: []
    Connections {
        target: apps
        ignoreUnknownSignals: true
        function onUrgentAcknowledged(appId, key) { acknowledgements = acknowledgements.concat([{appId:appId,key:key}]); }
    }
    IpcHandler {
        target: "parking-test"
        function snapshot(): string { return JSON.stringify({ready:apps.ready, parkingReady:apps.parkingReady,
            parkingBusy:apps.parkingBusy, parked:apps.parkedWindows, revision:apps.parkingRevision,
            last:apps.lastParkingReceipt, error:apps.error, items:apps.items, minimizeMode:apps.settings.minimizeMode}); }
        function seed(data: string): bool { const d=JSON.parse(data); return apps.fixtureSet(d.entries,d.windows); }
        function park(app: string, key: string): int { return apps.parkWindow(app,key); }
        function restore(app: string, key: string, mode: string): int { return apps.restoreWindow(app,key,mode); }
        function fifo(mode: string): int { return apps.restoreFifo(mode); }
        function recover(mode: string): int { return apps.recoverParked(mode); }
        function configure(data: string): bool { return apps.configure(JSON.parse(data)); }
        function activate(app: string): bool { return apps.activate(app); }
        function indicated(app: string, key: string): bool { return apps.activate(app,key); }
        function urgency(keys: string): bool {
            const urgent = JSON.parse(keys);
            apps._windows = apps._windows.map(w => Object.assign({}, w, {urgent:urgent.indexOf(w.key) >= 0, active:false}));
            apps._refresh(); return true;
        }
        function acks(): string { return JSON.stringify(acknowledgements); }
        function reverse(): bool { apps._windows = apps._windows.slice().reverse(); apps._refresh(); return true; }
    }
}
'''


class ParkingServiceTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix="omadocked-qml-parking-"); self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name); shutil.copytree(ROOT/"core",self.root/"core"); shutil.copytree(ROOT/"services",self.root/"services")
        (self.root/"shell.qml").write_text(SHELL)
        self.config=self.root/"config"/"pins.json"; self.journal=self.root/"state"/"parking.json"
        self.state=self.root/"fake-state.json"; self.log_path=self.root/"fake-argv.jsonl"; self.fake=self.root/"hyprctl"
        self.fake.write_text("""#!/usr/bin/python3
import json,os,re,sys,time
sys.path.insert(0, TEST_MODULE_PATH)
from pathlib import Path
state=Path(os.environ['FAKE_STATE']); log=Path(os.environ['FAKE_LOG']); args=sys.argv[1:]
with log.open('a') as f:f.write(json.dumps(args)+'\\n')
data=json.loads(state.read_text())
if args==['-j','clients']:print(json.dumps(data['clients']))
elif args==['-j','workspaces']:print(json.dumps(data['workspaces']))
elif args==['-j','activeworkspace']:print(json.dumps(data['activeworkspace']))
elif len(args)==2 and args[0]=='eval':
 from lua_compositor import execute_moves
 time.sleep(data.get('delay',0))
 for index, workspace in execute_moves(args[1], data['clients']):
  if not data.get('fail'):
   data['clients'][index]['workspace']={'name':workspace};data['clients'][index]['active']=False
 state.write_text(json.dumps(data));print('ok')
else:sys.exit(2)
""".replace("TEST_MODULE_PATH", repr(str(ROOT/"tests")))); self.fake.chmod(0o700)
        self.clients=[
            {"address":"0xaaa","pid":101,"class":"One","initialClass":"One","xwayland":False,"workspace":{"name":"1"},"monitor":0,"floating":False,"at":[1,2],"size":[300,200]},
            {"address":"0xbbb","pid":102,"class":"One","initialClass":"One","xwayland":True,"workspace":{"name":"2"},"monitor":1,"floating":True,"at":[4,5],"size":[500,400]},
            {"address":"0xfff","pid":999,"class":"Foreign","initialClass":"Foreign","xwayland":False,"workspace":{"name":"1"},"monitor":0,"floating":False,"at":[0,0],"size":[10,10]}]
        for index, client in enumerate(self.clients): client["stableId"] = format(index + 1, "x")
        self.write_state({"clients":self.clients,"workspaces":[{"name":"1"},{"name":"2"}],"activeworkspace":{"name":"1"}})
        self.proc=None

    def write_state(self,data):self.state.write_text(json.dumps(data))
    def start(self, platform="offscreen"):
        env=dict(safety.fixture_environment(),OMADOCKED_TEST_MODE="1",OMADOCKED_CONFIG_PATH=str(self.config),
                 OMADOCKED_PARKING_DISABLED="0",
                 OMADOCKED_PARKING_JOURNAL=str(self.journal),OMADOCKED_HYPRCTL=str(self.fake),
                 HYPRLAND_INSTANCE_SIGNATURE="fixture-session",FAKE_STATE=str(self.state),FAKE_LOG=str(self.log_path),
                 QT_QPA_PLATFORM=platform,QT_QUICK_BACKEND="software",QS_NO_RELOAD_POPUP="1")
        self.log=(self.root/"runtime.log").open("w+")
        try:
            self.proc=safety.spawn(["quickshell","-p",str(self.root/"shell.qml"),"--no-color"],required="offscreen", root=self.root, env=env,
                                       stdout=self.log,stderr=subprocess.STDOUT)
        except BaseException:
            self.log.close()
            raise
        deadline=time.monotonic()+8
        while time.monotonic()<deadline:
            self.assertIsNone(self.proc.poll(),(self.root/"runtime.log").read_text())
            value=self.call("snapshot",check=False)
            if value and value["ready"] and value["parkingReady"]:return value
            time.sleep(.04)
        self.fail((self.root/"runtime.log").read_text())
    def stop(self):
        if self.proc:
            self.proc.terminate(); self.proc.wait(timeout=5); self.proc=None; self.log.close()
    def tearDown(self):
        self.stop()
        if (self.root/"runtime.log").exists():
            text=(self.root/"runtime.log").read_text()
            for issue in ("ReferenceError:","TypeError:","Cannot assign","Binding loop"):
                self.assertNotIn(issue,text)
    def call(self,method,*args,check=True):
        result=safety.ipc(self.proc, ["quickshell","ipc","--pid",str(self.proc.pid),"call","--","parking-test",method,*map(str,args)],
                              text=True,capture_output=True,timeout=4)
        if not check and (result.returncode or not result.stdout.strip().startswith(("{","[","t","f","0","1","2","3","4","5","6","7","8","9"))):return None
        self.assertEqual(result.returncode,0,result.stdout+result.stderr);return json.loads(result.stdout)
    def seed(self):
        entries=[{"id":"one","name":"One","launchable":True,"icon":"application-x-executable"}]
        windows=[]
        for i,row in enumerate(self.clients[:2]):
            windows.append({"key":"fixture-"+str(i),"appId":"one","title":"PRIVATE TITLE "+str(i),"active":i==0,
                            "identity":{"address":row["address"],"pid":row["pid"],"class":row["class"],
                                "initialClass":row["initialClass"],"xwayland":row["xwayland"],"stableId":row["stableId"]},
                            "origin":{"workspace":row["workspace"]["name"],"monitor":row["monitor"],
                                "floating":row["floating"],"at":row["at"],"size":row["size"]}})
        self.assertTrue(self.call("seed",json.dumps({"entries":entries,"windows":windows})))
        return self.call("snapshot")
    def wait_revision(self,before,count=1):
        deadline=time.monotonic()+5
        while time.monotonic()<deadline:
            state=self.call("snapshot")
            if state["revision"]>=before+count and not state["parkingBusy"]:return state
            time.sleep(.03)
        self.fail("parking receipt timeout")

    def wait_mode(self,mode):
        deadline=time.monotonic()+4
        while time.monotonic()<deadline:
            state=self.call("snapshot")
            if state.get("minimizeMode")==mode:return state
            time.sleep(.03)
        self.fail("minimize setting receipt timeout")

    def test_urgent_parked_click_restores_exact_target_here_after_readback(self):
        self.start(); state=self.seed(); keys=state['items'][0]['windows']
        for key in keys:
            before=self.call('snapshot')['revision']
            self.assertGreater(self.call('park','one',key),0); self.wait_revision(before)
        self.call('urgency',' '+json.dumps([keys[1]]))
        data=json.loads(self.state.read_text()); data['delay']=.35; self.write_state(data)
        before=self.call('snapshot')['revision']
        self.assertTrue(self.call('activate','one'))
        self.assertEqual(self.call('acks'),[], 'submission is not acknowledgement')
        done=self.wait_revision(before)
        self.assertEqual(done['last']['key'],keys[1], 'urgent target outranks ordinary FIFO')
        self.assertEqual([r['key'] for r in done['parked']],[keys[0]])
        self.assertEqual(self.call('acks'),[{'appId':'one','key':keys[1]}])
        clients=json.loads(self.state.read_text())['clients']
        self.assertEqual(clients[1]['workspace']['name'],'1', 'HERE, not origin workspace 2')
        self.assertEqual(clients[2]['workspace']['name'],'1', 'foreign fixture untouched')

    def test_visible_urgent_click_never_minimizes_even_when_already_active(self):
        self.start(); state=self.seed(); keys=state['items'][0]['windows']
        self.call('urgency',' '+json.dumps([keys[1]]))
        self.assertTrue(self.call('activate','one'))
        self.assertEqual(self.call('acks'),[{'appId':'one','key':keys[1]}])
        self.assertTrue(self.call('activate','one'))
        self.assertEqual(self.call('snapshot')['revision'],0)
        self.assertEqual(self.call('snapshot')['parked'],[])

    def test_multiple_urgent_choice_is_stable_across_collection_order(self):
        self.start(); state=self.seed(); keys=state['items'][0]['windows']
        self.call('urgency',' '+json.dumps(keys)); self.call('reverse')
        self.assertTrue(self.call('activate','one'))
        self.assertEqual(self.call('acks'),[{'appId':'one','key':sorted(keys)[0]}])

    def test_queued_urgent_target_losing_urgency_never_falls_back(self):
        self.start(); state=self.seed(); keys=state['items'][0]['windows']
        self.assertGreater(self.call('park','one',keys[1]),0); self.wait_revision(0)
        self.call('urgency',' '+json.dumps([keys[1]]))
        data=json.loads(self.state.read_text()); data['delay']=.5; self.write_state(data)
        before=self.call('snapshot')['revision']
        self.assertGreater(self.call('park','one',keys[0]),0)
        self.assertTrue(self.call('activate','one'))
        self.call('urgency',' []')
        done=self.wait_revision(before,2)
        self.assertFalse(done['last']['ok'])
        self.assertEqual(set(r['key'] for r in done['parked']),set(keys))
        self.assertEqual(self.call('acks'),[])

    def test_stale_or_removed_indicated_urgent_key_never_acts_on_sibling(self):
        self.start(); state=self.seed(); keys=state['items'][0]['windows']
        self.assertFalse(self.call('indicated','one',keys[1]), 'cleared urgency is not ordinary activation')
        self.assertFalse(self.call('indicated','one','removed-key'))
        self.assertEqual(self.call('snapshot')['revision'],0)
        self.assertEqual(self.call('acks'),[])

    def test_failed_urgent_restore_retains_record_without_ack_or_fallback(self):
        self.start(); state=self.seed(); keys=state['items'][0]['windows']
        self.assertGreater(self.call('park','one',keys[1]),0); self.wait_revision(0)
        self.call('urgency',' '+json.dumps([keys[1]]))
        data=json.loads(self.state.read_text()); data['fail']=True; self.write_state(data)
        self.assertTrue(self.call('activate','one'))
        done=self.wait_revision(1)
        self.assertFalse(done['last']['ok'])
        self.assertEqual([r['key'] for r in done['parked']],[keys[1]])
        self.assertEqual(self.call('acks'),[])
        self.assertEqual(json.loads(self.state.read_text())['clients'][0]['workspace']['name'],'1')

    def test_ordinary_all_parked_preserves_fifo_here_and_explicit_origin(self):
        self.start(); state=self.seed(); keys=state['items'][0]['windows']
        for key in reversed(keys):
            before=self.call('snapshot')['revision']
            self.assertGreater(self.call('park','one',key),0); self.wait_revision(before)
        before=self.call('snapshot')['revision']
        self.assertTrue(self.call('activate','one')); done=self.wait_revision(before)
        self.assertEqual(done['last']['key'],keys[1])
        self.assertEqual(json.loads(self.state.read_text())['clients'][1]['workspace']['name'],'1')
        before=done['revision']
        self.assertGreater(self.call('restore','one',keys[0],'origin'),0); self.wait_revision(before)
        self.assertEqual(json.loads(self.state.read_text())['clients'][0]['workspace']['name'],'1')
        self.assertEqual(self.call('acks'),[])

    def test_exact_current_key_is_queued_without_optimistic_completion(self):
        self.start(); state=self.seed(); keys=self.call("snapshot")["items"][0]["windows"]
        data=json.loads(self.state.read_text());data["delay"]=.35;self.write_state(data)
        before=state["revision"]; transaction=self.call("park","one",keys[0])
        self.assertGreater(transaction,0)
        queued=self.call("snapshot");self.assertTrue(queued["parkingBusy"]);self.assertEqual(queued["parked"],[])
        done=self.wait_revision(before)
        self.assertEqual(done["last"],{"transactionId":transaction,"ok":True,"status":"parked","key":keys[0]})
        self.assertEqual(done["parked"],[{"key":keys[0],"state":"parked","sequence":1}])
        self.assertNotIn("PRIVATE TITLE",json.dumps(done));self.assertNotIn("PRIVATE TITLE",self.journal.read_text())
        foreign=next(r for r in json.loads(self.state.read_text())["clients"] if r["address"]=="0xfff")
        self.assertEqual(foreign["workspace"]["name"],"1")

    def test_primary_click_active_all_and_off_modes_use_verified_operations(self):
        self.start();state=self.seed();keys=state["items"][0]["windows"]
        before=state["revision"];self.assertTrue(self.call("activate","one"));done=self.wait_revision(before)
        self.assertEqual([r["key"] for r in done["parked"]],[keys[0]])
        before=done["revision"];self.assertGreater(self.call("recover","here"),0);self.wait_revision(before)
        self.assertTrue(self.call("configure",'{"minimizeMode":"all"}'));self.wait_mode("all");self.seed()
        before=self.call("snapshot")["revision"];self.assertTrue(self.call("activate","one"));done=self.wait_revision(before,2)
        self.assertEqual([r["key"] for r in done["parked"]],keys,"all mode preserves current stable window order")
        journal=json.loads(self.journal.read_text())
        self.assertFalse(journal["records"][0]["origin"]["floating"])
        self.assertTrue(journal["records"][1]["origin"]["floating"])
        self.assertEqual(journal["records"][1]["origin"]["at"],[4,5])
        self.assertEqual(journal["records"][1]["origin"]["size"],[500,400])
        before=done["revision"];self.assertGreater(self.call("recover","here"),0);self.wait_revision(before)
        self.assertTrue(self.call("configure",'{"minimizeMode":"off"}'));self.wait_mode("off");self.seed()
        before=self.call("snapshot")["revision"];self.assertTrue(self.call("activate","one"))
        time.sleep(.15);after=self.call("snapshot");self.assertEqual(after["revision"],before);self.assertEqual(after["parked"],[])

    def test_stale_regrouped_and_foreign_keys_never_queue(self):
        self.start();self.seed();keys=self.call("snapshot")["items"][0]["windows"]
        self.assertEqual(self.call("park","missing",keys[0]),0)
        self.assertEqual(self.call("park","one","missing"),0)
        changed=self.clients.copy();changed[0]=dict(changed[0],**{"class":"Regrouped"});data=json.loads(self.state.read_text());data["clients"]=changed;self.write_state(data)
        before=self.call("snapshot")["revision"]
        transaction=self.call("park","one",keys[0]);self.assertGreater(transaction,0)
        result=self.wait_revision(before)
        self.assertFalse(result["last"]["ok"]);self.assertEqual(result["parked"],[])

    def test_fifo_and_hidden_recovery_survive_controller_reload(self):
        self.start();self.seed();keys=self.call("snapshot")["items"][0]["windows"]
        before=self.call("snapshot")["revision"];self.assertGreater(self.call("park","one",keys[0]),0);self.wait_revision(before)
        self.stop();state=self.start();self.assertEqual([r["key"] for r in state["parked"]],[keys[0]])
        self.seed();fresh_keys=self.call("snapshot")["items"][0]["windows"]
        self.assertTrue(set(keys).isdisjoint(fresh_keys),"session keys must not alias different QObjects after controller reload")
        self.assertEqual(self.call("park","one",fresh_keys[1]),0,
                                     "startup recovery must precede new parking")
        before=state["revision"];transaction=self.call("recover","here");self.assertGreater(transaction,0)
        done=self.wait_revision(before);self.assertEqual(done["last"]["transactionId"],transaction);self.assertEqual(done["parked"],[])
        self.assertEqual(next(r for r in json.loads(self.state.read_text())["clients"] if r["address"]=="0xaaa")["workspace"]["name"],"1")


if __name__=="__main__":unittest.main()
