"""Production Socket UTF-8 regressions against owned byte-fragmenting Unix peers."""
import json
import socket
import threading
import time
import test_app_service as base

CAP = 2097152


class OverlapUtf8Tests(base.AppServiceTests):
    def setUp(self):
        super().setUp()
        self.plan = []
        self.commands = []
        self.eof = threading.Event()
        self.stopping = threading.Event()
        self.peers = []
        self.workers = []
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        path = str(self.root / 'utf8.sock')
        self.server.bind(path)
        self.server.listen()
        self.server.settimeout(.1)

        def handle(conn):
            conn.settimeout(2)
            try:
                command = conn.recv(128).decode('ascii')
                self.commands.append(command)
                chunks = list(self.plan) if command == 'j/monitors' else [b'[]']
                for chunk in chunks:
                    if chunk is None:
                        if conn.recv(1) == b'':
                            self.eof.set()
                        return
                    conn.sendall(chunk)
                    if len(chunks) > 1:
                        time.sleep(.02)
            except OSError:
                pass
            finally:
                conn.close()

        def serve():
            while not self.stopping.is_set():
                try:
                    conn, _ = self.server.accept()
                except socket.timeout:
                    continue
                except OSError:
                    break
                self.peers.append(conn)
                worker = threading.Thread(target=handle, args=(conn,))
                self.workers.append(worker)
                worker.start()

        self.server_thread = threading.Thread(target=serve)
        self.server_thread.start()
        (self.root / 'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "services"
ShellRoot {
    QtObject { id: ownedBackend; signal rawEvent(var event); property QtObject toplevels: QtObject { property var values: [] } }
    NativeOverlap { id: model; backend: ownedBackend }
    OverlapSnapshot { id: transport; source: model; backend: ownedBackend; socketPath: PATH }
    QtObject { id: probe; property string output: "owned" }
    IpcHandler {
        target: "app-test"
        function snapshot(): string { return JSON.stringify({ready:true,busy:model.busy,generation:model.generation,
            available:model.evaluate(probe.output,Qt.rect(0,600,500,80)).available,names:model.monitors.map(m=>m.name)}); }
        function enable(value:bool): bool { model.setConsumer("test",value); return true; }
        function name(value:string): bool { probe.output=value; return true; }
    }
}'''.replace('PATH', json.dumps(path)))
        self.start(extra_env={'QT_QPA_PLATFORM': 'offscreen'}, wrapped=False)

    def tearDown(self):
        try:
            super().tearDown()
        finally:
            self.stopping.set()
            self.server.close()
            for peer in self.peers:
                peer.close()
            self.server_thread.join(2)
            for worker in self.workers:
                worker.join(2)

    @staticmethod
    def reply(name):
        return json.dumps([dict(id=1, name=name, x=0, y=0,
                                activeWorkspace={'id': 1}, specialWorkspace={'id': 0})],
                          ensure_ascii=False).encode('utf-8')

    def begin(self, chunks, name='owned'):
        self.call('enable', 'false')
        self.plan = chunks
        self.eof.clear()
        self.call('name', name)
        generation = self.call('snapshot')['generation']
        self.call('enable', 'true')
        return generation

    def result(self, generation):
        deadline = time.monotonic() + 1.5
        while time.monotonic() < deadline:
            state = self.call('snapshot')
            if state['generation'] > generation and not state['busy']:
                self.call('enable', 'false')
                self.assertTrue(all(c in ('j/monitors', 'j/clients') for c in self.commands))
                return state
            time.sleep(.01)
        self.fail('No bounded completion: ' + repr(state))

    def test_multibyte_boundaries_preserve_exact_identity(self):
        # Every internal boundary of 2/3/4-byte scalars; combining/ZWJ sequences
        # and literal U+FFFD are valid identities, never normalized or rejected.
        for name in ('ownÉd', 'own€界d', 'own😀d', 'owne\u0301d', 'own👩\u200d💻d', 'own\ufffdd',
                     '\u0080\u07ff\u0800\ud7ff\ue000\uffff\U00010000\U0010ffff'):
            raw = self.reply(name)
            for cut in range(1, len(raw)):
                if raw[cut] & 0xc0 != 0x80:
                    continue
                with self.subTest(name=name, cut=cut):
                    state = self.result(self.begin([raw[:cut], raw[cut:]], name))
                    self.assertEqual(state['names'], [name])
                    self.assertTrue(state['available'])
        name = 'É€😀e\u0301'
        raw = self.reply(name)
        start = raw.index(name.encode())
        end = start + len(name.encode())
        chunks = [raw[:start]] + [raw[i:i+1] for i in range(start, end)] + [raw[end:]]
        state = self.result(self.begin(chunks, name))
        self.assertEqual(state['names'], [name])
        self.assertTrue(state['available'])
        name = 'É界😀e\u0301👩\u200d💻' * 128
        raw = self.reply(name)
        cuts = [i for i in range(1, len(raw)) if raw[i] & 0xc0 == 0x80]
        cut = cuts[len(cuts) // 2]
        state = self.result(self.begin([raw[:cut], raw[cut:]], name))
        self.assertEqual(state['names'], [name])
        self.assertTrue(state['available'])

    def test_malformed_utf8_is_not_silently_replaced(self):
        for bad in (b'\x80', b'\xc0\xaf', b'\xe0\x80\xaf', b'\xed\xa0\x80', b'\xf4\x90\x80\x80', b'\xf5\x80\x80\x80', b'\xc3x'):
            raw = self.reply('owned').replace(b'owned', b'own' + bad + b'd')
            cut = raw.index(bad) + 1
            for chunks in ([raw], [raw[:cut], raw[cut:]]):
                with self.subTest(bad=bad.hex(), chunks=len(chunks)):
                    state = self.result(self.begin(chunks))
                    self.assertFalse(state['available'])
                    self.assertEqual(state['names'], [])

    def test_truncation_and_partial_scalar_cancellation(self):
        for suffix in (b'\xc3', b'\xe2\x82', b'\xf0\x9f\x98'):
            raw = b'[{"name":"own' + suffix
            with self.subTest(suffix=suffix.hex()):
                self.assertFalse(self.result(self.begin([raw]))['available'])
                self.assertFalse(self.result(self.begin([raw, None]))['available'])
                self.assertTrue(self.eof.wait(1), 'Deadline must close partial-scalar socket')
        generation = self.begin([b'[{"name":"own\xc3', None])
        time.sleep(.1)
        self.assertTrue(self.call('snapshot')['busy'])
        self.call('enable', 'false')
        self.assertTrue(self.eof.wait(1), 'Disable must close partial-scalar socket')
        state = self.result(self.begin([self.reply('ownÉd')], 'ownÉd'))
        self.assertGreater(state['generation'], generation)
        self.assertEqual(state['names'], ['ownÉd'])
        self.assertTrue(state['available'])
        self.begin([b'[{"name":"own\xf0\x9f', None])
        time.sleep(.1)
        self.assertTrue(self.call('snapshot')['busy'])
        self.stop()
        self.assertTrue(self.eof.wait(1), 'Unload must close partial-scalar socket')

    def test_response_string_unit_limit_with_multibyte_data(self):
        name = 'own😀d'
        raw = self.reply(name)
        units = len(raw.decode('utf-8').encode('utf-16-le')) // 2
        for extra in (0, 1):
            with self.subTest(extra=extra):
                state = self.result(self.begin([b' ' * (CAP - units + extra) + raw, None], name))
                self.assertEqual(state['available'], extra == 0)
                self.assertTrue(self.eof.wait(1), 'Completion/limit closes actual socket')


for _name in dir(base.AppServiceTests):
    if _name.startswith('test_'):
        setattr(OverlapUtf8Tests, _name, None)
