"""Real Quickshell sockets against an owned Unix server; no compositor requests."""
import json
import socket
import threading
import time
import test_app_service as base

class OverlapSocketTests(base.AppServiceTests):
    def test_owned_socket_receipts_and_cancellation(self):
        self.assertTrue((self.root/'services/OverlapSnapshot.qml').exists(), 'Acknowledged bounded snapshot transport required')
        path=str(self.root/'owned.sock')
        server=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); server.bind(path); server.listen(); server.settimeout(.1)
        stop=threading.Event(); requests=[]; mode=['ok']; clients=[[]]; connections=[]
        monitors=[dict(id=1,name='owned',x=0,y=0,activeWorkspace={'id':1},specialWorkspace={'id':0})]
        def serve():
            while not stop.is_set():
                try: conn,_=server.accept()
                except socket.timeout: continue
                except OSError: break
                connections.append(conn)
                try:
                    command=conn.recv(128).decode(); requests.append(command)
                    if mode[0]=='stall': continue
                    data=monitors if command=='j/monitors' else clients[0]
                    raw=b'broken' if mode[0]=='bad' else json.dumps(data).encode()
                    # Real fragmented stream, empty arrays are valid acknowledged snapshots.
                    conn.sendall(raw[:2]); time.sleep(.005); conn.sendall(raw[2:])
                except OSError: pass
                finally:
                    if mode[0]!='stall': conn.close()
        thread=threading.Thread(target=serve); thread.start()
        self.addCleanup(lambda: [c.close() for c in connections])
        self.addCleanup(server.close)
        self.addCleanup(lambda: thread.join(timeout=2))
        self.addCleanup(stop.set)
        (self.root/'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "services"
ShellRoot {
    QtObject { id: backend; signal rawEvent(var event); property QtObject toplevels: QtObject { property var values: [] } }
    NativeOverlap { id: model; backend: backend }
    OverlapSnapshot { id: transport; source: model; socketPath: SOCKET; backend: backend }
    IpcHandler {
        target:"app-test"
        function snapshot(): string { return JSON.stringify({ready:true,active:model.active,busy:model.busy,policy:model.evaluate("owned",Qt.rect(0,600,500,80))}); }
        function enable(value: bool): bool { model.setConsumer("owned",value); return true; }
        function refresh(): bool { model.refresh(); return true; }
    }
}'''.replace('SOCKET',json.dumps(path)))
        self.start(extra_env={'QT_QPA_PLATFORM':'offscreen'},wrapped=False)
        time.sleep(.15); self.assertEqual(requests,[])
        self.call('enable','true')
        def wait_for(predicate):
            end=time.monotonic()+2
            while time.monotonic()<end:
                state=self.call('snapshot')
                if predicate(state): return state
                time.sleep(.02)
            self.fail(state)
        wait_for(lambda s:s['policy']['available'])
        clients[0]=[dict(address='0xowned',mapped=True,hidden=False,pinned=False,monitor=1,workspace={'id':1},at=[0,600],size=[100,100],fullscreen=0)]
        wait_for(lambda s:s['policy']['overlap'])
        mode[0]='bad'; self.call('refresh')
        wait_for(lambda s:not s['policy']['available'])
        mode[0]='ok'; self.call('refresh'); wait_for(lambda s:s['policy']['available'])
        mode[0]='stall'; self.call('refresh'); wait_for(lambda s:s['busy'])
        self.call('enable','false'); state=self.call('snapshot'); self.assertFalse(state['busy']); self.assertFalse(state['policy']['available'])
        connections[-1].settimeout(1)
        self.assertEqual(connections[-1].recv(1),b'', 'Disable closes actual owned request socket')
        n=len(requests); time.sleep(1.15); self.assertEqual(len(requests),n)
        self.assertTrue(all(c in ('j/monitors','j/clients') for c in requests))
        self.call('enable','true'); wait_for(lambda s:s['busy'])
        end=time.monotonic()+1
        while len(requests)==n and time.monotonic()<end: time.sleep(.01)
        self.stop()
        connections[-1].settimeout(1)
        self.assertEqual(connections[-1].recv(1),b'', 'Unload closes actual owned request socket')

for _name in dir(base.AppServiceTests):
    if _name.startswith('test_'): setattr(OverlapSocketTests,_name,None)
