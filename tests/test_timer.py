import unittest
from timer import Timer

class TimerTests(unittest.TestCase):
    def make(self, repeats=2, rest=10):
        t=Timer()
        t.start(dict(message='Встань <&>', interval=1, rest=rest, repeats=repeats), 100)
        return t
    def test_full_cycles(self):
        t=self.make()
        self.assertEqual(t.tick(159), [])
        self.assertEqual(t.tick(160)[0][1], 'Встань <&>')
        self.assertEqual(t.phase,'rest')
        t.tick(170)
        self.assertEqual(t.phase,'work')
        t.tick(230)
        self.assertEqual(t.completed,2)
        t.tick(240)
        self.assertEqual(t.phase,'stopped')
    def test_pause_resume(self):
        for phase, instant in [('work',120),('rest',162)]:
            t=self.make()
            if phase=='rest': t.tick(160)
            t.toggle(instant)
            left=t.status(instant)['seconds']
            self.assertEqual(t.tick(9999), [])
            self.assertEqual(t.status(9999)['seconds'],left)
            t.toggle(10000)
            self.assertEqual(t.deadline,10000+left)
    def test_resume_after_sleep_no_burst(self):
        t=self.make()
        self.assertEqual(len(t.tick(50000)),1)
        self.assertEqual(t.completed,1)
        self.assertEqual(t.deadline,50010)
    def test_infinite_zero_break(self):
        t=self.make(0,0)
        for n in range(20):
            t.tick(t.deadline)
            t.tick(t.deadline)
        self.assertEqual(t.phase,'work')
        self.assertEqual(t.completed,20)
    def test_invalid(self):
        for key,value in [('interval',0),('interval',float('nan')),('rest',-1),('repeats',1.1),('message','')]:
            t=self.make()
            c=dict(t.config); c[key]=value
            with self.assertRaises(ValueError): t.start(c,0)
    def test_restart(self):
        t=self.make(); t.tick(160); t.toggle(162)
        t.start(t.config,200)
        self.assertEqual(t.completed,0)
        self.assertFalse(t.paused)
        self.assertEqual(t.deadline,260)

if __name__=='__main__': unittest.main()
