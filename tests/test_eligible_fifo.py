"""FIFO progress must never destroy blocked recovery evidence."""
import json
import unittest
import test_parking_helper as ph


class EligibleFifo(unittest.TestCase):
    def test_repeated_fifo_preserves_blocked_evidence(self):
        for kind in ('replacement', 'legacy', 'all-blocked', 'session'):
            with self.subTest(kind=kind):
                f = ph.ParkingHelperTests(); f.setUp()
                try:
                    p = f.start()
                    self.assertTrue(f.park(p, 'a', '0xaaa', 101, 'FixtureA', '1')['ok'])
                    self.assertTrue(f.park(p, 'b', '0xbbb', 102, 'FixtureB', '2', True, 2)['ok'])
                    if kind == 'legacy':
                        p.close()
                        journal = json.loads(f.journal.read_text())
                        del journal['records'][0]['identity']['stableId']
                        f.journal.write_text(json.dumps(journal)); p = f.start()
                    elif kind == 'session':
                        p.close(); p = f.start('different-session')
                    else:
                        data = json.loads(f.state.read_text())
                        data['clients'][0]['stableId'] = 'a2'
                        if kind == 'all-blocked': data['clients'][1]['stableId'] = 'b2'
                        f.write_state(data)
                    before = json.loads(f.journal.read_text())['records'][0]
                    result = p.request(dict(id=3, op='restore-fifo', mode='here'))
                    if kind in ('replacement', 'legacy'):
                        self.assertTrue(result['ok']); self.assertEqual(result['key'], 'b')
                    else:
                        self.assertFalse(result['ok']); self.assertEqual(result['status'], 'blocked')
                    self.assertIn('a', result['blocked'])
                    for i in range(2):
                        result = p.request(dict(id=4+i, op='restore-fifo', mode='here'))
                        self.assertFalse(result['ok']); self.assertEqual(result['status'], 'blocked')
                        self.assertIn('a', result['blocked'])
                    after = json.loads(f.journal.read_text())
                    self.assertEqual(after['records'][0], before)
                    self.assertEqual(json.loads(f.state.read_text())['clients'][0]['workspace']['name'], 'special:Omadocked')
                finally:
                    f.tearDown(); f.doCleanups()
