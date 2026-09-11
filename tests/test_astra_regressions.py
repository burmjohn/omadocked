"""Independent falsifiable expectations: failures are audit reproductions, not fixes."""
from pathlib import Path
import sys,json,subprocess,os,tempfile,unittest,importlib.util
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tests'))
import test_parking_helper as ph

def load(name,path):
 s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
store=load('audit_store',ROOT/'services/config_store.py')
class AuditTests(unittest.TestCase):
 def parking(self):
  f=ph.ParkingHelperTests(); f.setUp(); self.addCleanup(f.doCleanups); self.addCleanup(f.tearDown); return f
 def test_parking_helper_loss_completes_public_receipt_and_clears_queue(self):
  import test_parking_service as ps,time
  f=ps.ParkingServiceTests();f.setUp();self.addCleanup(f.doCleanups);self.addCleanup(f.tearDown)
  helper=f.root/'services/parking_store.py'
  helper.write_text(helper.read_text().replace('        if operation == "status":','        if operation == "status":\n            if request["id"] > 1: raise SystemExit(0)'))
  f.start();state=f.seed();keys=state['items'][0]['windows']
  data=json.loads(f.state.read_text());data['delay']=0.35;f.write_state(data)
  first=f.call('park','one',keys[0]);second=f.call('park','one',keys[1]);self.assertGreater(second,first)
  deadline=time.monotonic()+4
  while time.monotonic()<deadline:
   state=f.call('snapshot')
   if not state['parkingReady']:break
   time.sleep(.02)
  print('helper-loss observation:',json.dumps({k:state[k] for k in ['parkingReady','parkingBusy','last','revision']}))
  self.assertEqual(state['last']['transactionId'],first,'Internal status ID zero must not replace original operation receipt')
  self.assertFalse(state['parkingBusy'],'Failed helper must flush queued operations')
 def test_same_process_replacement_identity_must_not_restore_foreign_window(self):
  f=self.parking();data=f.base;data['clients'][0]['stableId']='a1';f.write_state(data)
  p=f.start();self.assertTrue(f.park(p,'a','0xaaa',101,'FixtureA','1')['ok'])
  data=json.loads(f.state.read_text());data['clients'][0]['stableId']='a2';f.write_state(data)
  receipt=p.request({'id':2,'op':'restore','key':'a','mode':'here'})
  self.assertFalse(receipt['ok'],'Address/PID/class tuple aliases a replacement; stable window identity was ignored')
 def test_external_close_during_session_must_not_block_fifo(self):
  f=self.parking();p=f.start();self.assertTrue(f.park(p,'a','0xaaa',101,'FixtureA','1')['ok'])
  data=json.loads(f.state.read_text());data['clients']=[r for r in data['clients'] if r['address']!='0xaaa'];f.write_state(data)
  status=p.request({'id':3,'op':'status'})
  self.assertEqual(status['records'],[], 'Closed windows should be reconciled without restarting the helper')
 def test_fifo_last_recovery_must_clear_startup_gate(self):
  f=self.parking();p=f.start();self.assertTrue(f.park(p,'a','0xaaa',101,'FixtureA','1')['ok']);p.close()
  p=f.start();self.assertTrue(p.request({'id':2,'op':'restore-fifo','mode':'here'})['ok'])
  status=p.request({'id':3,'op':'status'});self.assertEqual(status['records'],[])
  self.assertFalse(status['recoveryRequired'],'Successful final FIFO recovery must unblock new parking')
 def test_final_lkg_failure_must_report_main_committed(self):
  with tempfile.TemporaryDirectory(prefix='astra-config-') as tmp:
   path=Path(tmp)/'pins.json';s=store.Store(str(path));self.addCleanup(s.close)
   before='{"version":2,"pins":[]}\n';after='{"version":2,"pins":["fixture"]}\n'
   s.commit(dict(id=1,op='commit',expected='',missing=True,replacement=before,fallback=before))
   original=s.atomic_write;calls=[]
   def fail_final(name,text):
    calls.append(name)
    if len(calls)==3:raise OSError('injected final LKG failure')
    original(name,text)
   s.atomic_write=fail_final
   try:receipt=s.request(dict(id=2,op='commit',expected=before,missing=False,replacement=after,fallback=before))
   except OSError:receipt={'id':2,'ok':False,'error':'storage'} # exact main() exception mapping
   self.assertEqual(path.read_text(),after,'Main was already committed and read back')
   self.assertTrue(receipt['ok'],'Verified main commit must not be reported as entirely failed')
 def test_fifo_main_is_rejected_without_blocking_transaction(self):
  with tempfile.TemporaryDirectory(prefix='astra-fifo-') as tmp:
   path=Path(tmp)/'pins.json';p=subprocess.Popen([sys.executable,str(ROOT/'services/config_store.py'),str(path)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
   try:
    self.assertTrue(json.loads(p.stdout.readline())['ok']);os.mkfifo(path)
    request=dict(id=1,op='commit',expected='',missing=True,replacement='{}',fallback='{}')
    p.stdin.write(json.dumps(request)+'\n');p.stdin.flush()
    import select
    readable,_,_=select.select([p.stdout],[],[],0.7)
    self.assertTrue(readable,'FIFO blocks Store.read while lock stays held; there is no QML operation deadline')
   finally:
    p.terminate();p.wait(timeout=3)
    for stream in [p.stdin,p.stdout,p.stderr]:stream.close()
if __name__=='__main__':unittest.main(verbosity=2)
