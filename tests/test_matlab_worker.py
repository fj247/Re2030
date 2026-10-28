"""Mailbox and native launch contract, using a process double (not MATLAB)."""
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

from sim2030.matlab_worker import MatlabWorker, _read, _write


def wait_for(predicate):
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(.01)
    raise AssertionError('Worker did not reach expected state')


class WorkerTests(unittest.TestCase):
    def test_windows_persistent_process_runs_two_mailbox_commands_without_restart(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source's directory"
            source.mkdir()
            directory = root / 'worker'
            start = threading.Event()
            calls = []
            class Process:
                returncode = None
                def poll(self):
                    return self.returncode
                def wait(self):
                    start.wait(3)
                    _write(directory / 'ready.json', {'ready':True})
                    while not (directory / 'SHUTDOWN').exists():
                        command = _read(directory / 'command.json')
                        if command:
                            calls.append(command)
                            (directory / 'command.json').unlink()
                            _write(directory / (command['id']+'.json'), {'exitCode':0})
                        time.sleep(.01)
                    self.returncode = 0
                    return 0
            process = Process()
            with patch('sim2030.matlab_worker.sys.platform','win32'), \
                    patch('sim2030.matlab_worker.subprocess.Popen',return_value=process) as popen:
                worker = MatlabWorker(directory,'matlab.exe',source,'generation')
                try:
                    wait_for(lambda:worker.process is not None)
                    self.assertEqual(worker.status()['phase'],'preparing')
                    with self.assertRaisesRegex(ValueError,'相关装置启动中'):
                        worker.run(root/'not-started.json','bds_capture_entry',root/'generation.log')
                    self.assertFalse((directory/'command.json').exists())
                    start.set()
                    wait_for(lambda:worker.status()['phase']=='ready')
                    for number in (1,2):
                        self.assertEqual(worker.run(root/f'request{number}.json','bds_capture_entry',root/f'log{number}.log'),0)
                    self.assertEqual(popen.call_count,1)
                    self.assertEqual(len(calls),2)
                    args = popen.call_args.args[0]
                    self.assertIn('-wait',args)
                    self.assertIn('-batch',args)
                    self.assertEqual(popen.call_args.kwargs['cwd'],str(source))
                    script = (directory/'launch.m').read_text()
                    self.assertIn("source''s directory",script)
                    self.assertIn('getReport',script)
                    self.assertNotIn('bds_generate(',script)
                finally:
                    start.set()
                    worker.close()
                    worker.boot.join(3)
                self.assertFalse(worker.boot.is_alive())
                self.assertEqual(worker.status()['phase'],'stopped')

    def test_exited_process_does_not_report_stale_readiness(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with patch('sim2030.matlab_worker.subprocess.Popen',side_effect=OSError('license launcher missing')):
                worker = MatlabWorker(root,'matlab',root,'analysis')
                worker.boot.join(3)
            _write(root/'ready.json',{'ready':True})
            self.assertEqual(worker.status()['phase'],'failed')
            self.assertIn('license launcher missing',worker.status()['error'])
            worker.close()
