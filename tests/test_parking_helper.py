"""P3-02/P3-03 parking helper tests; fake compositor only."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "services/parking_store.py"


class ParkingProcess:
    def __init__(self, journal, executable, session="fixture-session"):
        env = dict(os.environ, OMADOCKED_TEST_MODE="1", OMADOCKED_HYPRCTL=str(executable),
                   FAKE_JOURNAL=str(journal), HYPRLAND_INSTANCE_SIGNATURE=session)
        self.proc = subprocess.Popen([sys.executable, str(HELPER), str(journal)], stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1, env=env)
        self.ready = self.read()

    def read(self):
        line = self.proc.stdout.readline()
        if not line:
            raise AssertionError(self.proc.stderr.read())
        return json.loads(line)

    def request(self, value):
        self.proc.stdin.write(json.dumps(value, separators=(",", ":")) + "\n")
        self.proc.stdin.flush()
        return self.read()

    def close(self):
        if self.proc.poll() is None:
            self.proc.terminate()
        self.proc.wait(timeout=3)
        for stream in (self.proc.stdin, self.proc.stdout, self.proc.stderr):
            if stream is not None and not stream.closed:
                stream.close()


class ParkingHelperTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="omadocked-parking-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.journal = self.root / "private state" / "parking.json"
        self.state = self.root / "clients.json"
        self.log = self.root / "argv.jsonl"
        self.hyprctl = self.root / "hyprctl"
        self.hyprctl.write_text("""#!/usr/bin/python3
import json,os,re,sys
sys.path.insert(0, TEST_MODULE_PATH)
from pathlib import Path
state=Path(os.environ['FAKE_STATE']); log=Path(os.environ['FAKE_LOG'])
args=sys.argv[1:]
with log.open('a') as f: f.write(json.dumps(args,separators=(',',':'))+'\\n')
data=json.loads(state.read_text())
if args == ['-j','clients']: print(json.dumps(data['clients']))
elif args == ['-j','workspaces']: print(json.dumps(data['workspaces']))
elif args == ['-j','activeworkspace']: print(json.dumps(data['activeworkspace']))
elif len(args)==2 and args[0]=='eval':
    from lua_compositor import execute_moves
    moves=execute_moves(args[1], data['clients'])
    journal=json.loads(Path(os.environ['FAKE_JOURNAL']).read_text())
    data['journalBeforeMove']=journal['records'][0]['state']
    if not data.get('failMove'):
        for index, workspace in moves: data['clients'][index]['workspace']={'name':workspace}
    state.write_text(json.dumps(data))
    print('ok')
else: sys.exit(2)
""".replace("TEST_MODULE_PATH", repr(str(ROOT/"tests"))))
        self.hyprctl.chmod(0o700)
        self.base = {
            "clients": [
                {"address":"0xaaa","pid":101,"class":"FixtureA","initialClass":"FixtureA","xwayland":False,
                 "workspace":{"name":"1"},"monitor":0,"floating":False,"at":[1,2],"size":[300,200]},
                {"address":"0xbbb","pid":102,"class":"FixtureB","initialClass":"FixtureB","xwayland":True,
                 "workspace":{"name":"2"},"monitor":1,"floating":True,"at":[4,5],"size":[500,400]},
                {"address":"0xforeign","pid":999,"class":"Foreign","initialClass":"Foreign","xwayland":False,
                 "workspace":{"name":"1"},"monitor":0,"floating":False,"at":[0,0],"size":[10,10]}],
            "workspaces":[{"name":"1"},{"name":"2"}], "activeworkspace":{"name":"1"}}
        for index, client in enumerate(self.base["clients"]):
            client["stableId"] = format(index + 1, "x")
        self.write_state(self.base)
        self.processes=[]

    def tearDown(self):
        for process in reversed(self.processes): process.close()

    def write_state(self, value): self.state.write_text(json.dumps(value))
    def start(self, session="fixture-session", journal=None):
        old_state, old_log = os.environ.get("FAKE_STATE"), os.environ.get("FAKE_LOG")
        os.environ["FAKE_STATE"], os.environ["FAKE_LOG"] = str(self.state), str(self.log)
        try: process=ParkingProcess(journal or self.journal,self.hyprctl,session)
        finally:
            if old_state is None: os.environ.pop("FAKE_STATE",None)
            else: os.environ["FAKE_STATE"]=old_state
            if old_log is None: os.environ.pop("FAKE_LOG",None)
            else: os.environ["FAKE_LOG"]=old_log
        self.processes.append(process); return process
    def identity(self,key,address,pid,klass,xwayland=False):
        client = next((r for r in json.loads(self.state.read_text())["clients"] if r["address"] == address), {})
        return {"key":key,"address":address,"pid":pid,"class":klass,"initialClass":klass,"xwayland":xwayland,
                "stableId":client.get("stableId", "1")}
    def park(self,p,key,address,pid,klass,workspace,xwayland=False,request_id=1):
        return p.request({"id":request_id,"op":"park","window":self.identity(key,address,pid,klass,xwayland),
                          "origin":{"workspace":workspace,"monitor":0,"floating":False,"at":[1,2],"size":[300,200]}})

    def test_park_writes_and_reads_journal_before_exact_argv_move_and_verifies(self):
        p=self.start(); self.assertEqual(p.ready,{"type":"ready","ok":True,"pending":0,"blocked":0})
        result=self.park(p,"session-key-a","0xaaa",101,"FixtureA","1")
        self.assertEqual(result,{"id":1,"ok":True,"status":"parked","key":"session-key-a"})
        journal=json.loads(self.journal.read_text())
        self.assertEqual(journal["session"],"fixture-session")
        self.assertEqual(journal["records"][0]["state"],"parked")
        self.assertEqual(journal["records"][0]["identity"],self.identity("session-key-a","0xaaa",101,"FixtureA"))
        self.assertNotIn("title",self.journal.read_text().lower())
        rows=json.loads(self.state.read_text())["clients"]
        self.assertEqual(json.loads(self.state.read_text())["journalBeforeMove"],"parking")
        self.assertEqual(next(r for r in rows if r["address"]=="0xaaa")["workspace"]["name"],"special:Omadocked")
        self.assertEqual(next(r for r in rows if r["address"]=="0xforeign")["workspace"]["name"],"1")
        argv=[json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertTrue(any(a[0]=="eval" and "address:0xaaa" in a[1] and "special:Omadocked" in a[1] for a in argv))
        self.assertFalse(any("shell" in " ".join(a) for a in argv))

    def test_full_identity_mismatch_is_inert_even_when_pid_matches(self):
        p=self.start()
        for i,changed in enumerate([
            self.identity("k","0xaaa",101,"Wrong"), self.identity("k","0xaaa",101,"FixtureA")|{"initialClass":"Wrong"},
            self.identity("k","0xaaa",101,"FixtureA",True), self.identity("k","0xmissing",101,"FixtureA")],1):
            response=p.request({"id":i,"op":"park","window":changed,"origin":{"workspace":"1","monitor":0,
                "floating":False,"at":[1,2],"size":[300,200]}})
            self.assertFalse(response["ok"])
        self.assertFalse(self.journal.exists())
        self.assertEqual(json.loads(self.state.read_text()),self.base)
        self.assertFalse(any(a[0]=="eval" for a in map(json.loads,self.log.read_text().splitlines())))

    def test_failed_move_is_not_optimistically_parked_and_remains_recoverable(self):
        data=dict(self.base); data["failMove"]=True; self.write_state(data)
        p=self.start(); response=self.park(p,"k","0xaaa",101,"FixtureA","1")
        self.assertEqual(response,{"id":1,"ok":False,"status":"unverified","key":"k"})
        record=json.loads(self.journal.read_text())["records"][0]
        self.assertEqual(record["state"],"parking")
        self.assertEqual(record["identity"]["address"],"0xaaa")

    def test_fifo_restore_is_oldest_parked_not_request_or_mru_order(self):
        p=self.start()
        self.assertTrue(self.park(p,"old","0xaaa",101,"FixtureA","1",request_id=10)["ok"])
        data=json.loads(self.state.read_text()); data["clients"][1]["workspace"]={"name":"2"}; self.write_state(data)
        self.assertTrue(self.park(p,"new","0xbbb",102,"FixtureB","2",True,11)["ok"])
        first=p.request({"id":12,"op":"restore-fifo","mode":"here"})
        second=p.request({"id":13,"op":"restore-fifo","mode":"here"})
        self.assertEqual([first["key"],second["key"]],["old","new"])
        self.assertEqual(json.loads(self.journal.read_text())["records"],[])

    def test_restore_here_uses_fresh_normal_workspace_and_origin_unavailable_is_explicit(self):
        p=self.start(); self.assertTrue(self.park(p,"k","0xbbb",102,"FixtureB","2",True)["ok"])
        data=json.loads(self.state.read_text()); data["activeworkspace"]={"name":"special:elsewhere"}; self.write_state(data)
        response=p.request({"id":2,"op":"restore","key":"k","mode":"here"})
        self.assertEqual(response,{"id":2,"ok":False,"status":"current-workspace-unavailable","key":"k"})
        self.assertEqual(len(json.loads(self.journal.read_text())["records"]),1)
        data["activeworkspace"]={"name":"1"}; data["workspaces"]=[{"name":"1"}]; self.write_state(data)
        response=p.request({"id":3,"op":"restore","key":"k","mode":"origin"})
        self.assertEqual(response,{"id":3,"ok":False,"status":"origin-unavailable","key":"k"})
        self.assertEqual(len(json.loads(self.journal.read_text())["records"]),1)
        response=p.request({"id":4,"op":"restore","key":"k","mode":"here"})
        self.assertEqual(response,{"id":4,"ok":True,"status":"restored","key":"k","workspace":"1"})

    def test_empty_stale_session_journal_is_adopted_before_new_park(self):
        self.journal.parent.mkdir(parents=True)
        self.journal.write_text(json.dumps({"version": 1, "session": "old-login", "nextSequence": 1, "records": []}) + "\n")
        self.journal.chmod(0o600)
        p = self.start(session="new-login")
        self.assertEqual(p.ready, {"type": "ready", "ok": True, "pending": 0, "blocked": 0})
        result = self.park(p, "k", "0xaaa", 101, "FixtureA", "1")
        self.assertEqual(result, {"id": 1, "ok": True, "status": "parked", "key": "k"})
        journal = json.loads(self.journal.read_text())
        self.assertEqual(journal["session"], "new-login")
        status = p.request({"id": 2, "op": "status"})
        self.assertEqual(status["keys"], ["k"])
        self.assertEqual(status["blocked"], [])
        restore = p.request({"id": 3, "op": "restore", "key": "k", "mode": "here"})
        self.assertTrue(restore["ok"], restore)
        self.assertEqual(restore["status"], "restored")

    def test_startup_recovery_precedes_new_parking_and_stale_session_or_identity_is_blocked(self):
        p=self.start(); self.assertTrue(self.park(p,"k","0xaaa",101,"FixtureA","1")["ok"]); p.close()
        restarted=self.start(); self.assertEqual(restarted.ready,{"type":"ready","ok":True,"pending":1,"blocked":0})
        self.assertEqual(restarted.request({"id":2,"op":"status"})["keys"],["k"])
        restarted.close()
        stale=self.start(session="other-session")
        self.assertEqual(stale.ready,{"type":"ready","ok":True,"pending":0,"blocked":1})
        self.assertEqual(stale.request({"id":3,"op":"recover","mode":"here"})["status"],"blocked")
        self.assertEqual(stale.request({"id":4,"op":"park","window":self.identity("new","0xaaa",101,"FixtureA"),
            "origin":{"workspace":"special:Omadocked","monitor":0,"floating":False,"at":[1,2],"size":[3,4]}})["status"],"recovery-required")

    def test_external_close_is_reconciled_but_address_reuse_and_regroup_stay_blocked(self):
        p=self.start(); self.assertTrue(self.park(p,"k","0xaaa",101,"FixtureA","1")["ok"]); p.close()
        data=json.loads(self.state.read_text()); data["clients"]=[]; self.write_state(data)
        closed=self.start(); self.assertEqual(closed.ready["pending"],0)
        self.assertEqual(json.loads(self.journal.read_text())["records"],[])
        closed.close()
        self.write_state(self.base); p=self.start(); self.assertTrue(self.park(p,"k2","0xaaa",101,"FixtureA","1")["ok"]); p.close()
        data=json.loads(self.state.read_text()); data["clients"][0]["class"]="Regrouped"; self.write_state(data)
        regrouped=self.start(); self.assertEqual(regrouped.ready["blocked"],1)
        self.assertEqual(regrouped.request({"id":8,"op":"restore","key":"k2","mode":"here"})["status"],"identity-mismatch")
        self.assertEqual(data["clients"][0]["workspace"]["name"],"special:Omadocked")

    def test_group_partial_failure_preserves_failed_record_and_never_moves_foreign(self):
        p=self.start(); self.assertTrue(self.park(p,"a","0xaaa",101,"FixtureA","1")["ok"])
        data=json.loads(self.state.read_text()); data["clients"][1]["workspace"]={"name":"2"}; self.write_state(data)
        self.assertTrue(self.park(p,"b","0xbbb",102,"FixtureB","2",True,2)["ok"])
        data=json.loads(self.state.read_text()); data["clients"][1]["class"]="Changed"; self.write_state(data)
        result=p.request({"id":3,"op":"recover","mode":"here"})
        self.assertEqual(result["status"],"partial")
        self.assertEqual(result["restored"],["a"]); self.assertEqual(result["blocked"],["b"])
        self.assertEqual([r["identity"]["key"] for r in json.loads(self.journal.read_text())["records"]],["b"])
        foreign=next(r for r in json.loads(self.state.read_text())["clients"] if r["address"]=="0xforeign")
        self.assertEqual(foreign["workspace"]["name"],"1")

    def test_unsafe_journal_and_injection_strings_are_rejected_without_shell_interpretation(self):
        bad=self.root / "x" / ".." / "parking.json"
        p=self.start(journal=bad); self.assertEqual(p.ready,{"type":"ready","ok":False,"error":"unsafe"})
        marker=self.root / "PWNED"
        valid=self.start()
        response=self.park(valid,"k","0xaaa;touch "+str(marker),101,"FixtureA","1")
        self.assertFalse(response["ok"]); self.assertFalse(marker.exists()); self.assertFalse(self.journal.exists())


if __name__ == "__main__": unittest.main()
