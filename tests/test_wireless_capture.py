"""Controller contract tests with a test double, NOT MATLAB waveform validation."""
import hashlib
import json
from pathlib import Path
import struct
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

from sim2030.wireless_capture import CaptureManager, write_json, matlab_quote
from sim2030.presentation.server import PresentationServer
from sim2030.application import Application

ROOT = Path(__file__).resolve().parents[1]
SCENE = str(ROOT / 'scenarios/substation-time-attack.json')


def wait_for(predicate, timeout=5):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if predicate():
            return
        time.sleep(.01)
    raise AssertionError('Worker did not reach expected state')


class CaptureTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.manager = CaptureManager(self.root / 'state')
        self.addCleanup(self.manager.close)
        self.entered = threading.Event()
        self.manager._invoke = self.fake_matlab
        self.manager.configure({'enabled': True, 'output_directory': str(self.root / 'captures'), 'matlab': sys.executable})

    def fake_matlab(self, task, entry, log):
        folder = Path(task['directory'])
        if entry == 'bds_capture_analyze':
            write_json(folder / 'detector/analysis.json', {'overview':'saved','presence':'insufficient_samples'})
            return 0
        self.entered.set()
        detector = folder / 'detector'
        (detector / 'segment_000001.iq.f32.partial').write_bytes(struct.pack('<ffff', 1, 0, -1, 0))
        while not (folder / 'STOP').exists():
            time.sleep(.01)
        (detector / 'segment_000001.iq.f32.partial').rename(detector / 'segment_000001.iq.f32')
        private = folder / 'private/generated'
        private.mkdir(parents=True)
        metadata = private / 'wave.json'
        write_json(metadata, {'verification':{'structuralPassed':True},'sampleRateHz':8184000,
                 'configuration':{'txHardware':{'name':'transmitter_A','seed':123}},
                 'numberComplexSamples':2,'segments':[{'fileName':'../../detector/segment_000001.iq.f32',
                 'sampleCount':2,'startSample':0}]})
        write_json(folder / 'generated.json', {'metadataFile':str(metadata),'empty':False})
        return 0

    def finish(self, task_id):
        self.manager.stop(task_id)
        wait_for(lambda: self.manager.task(task_id)['analysis'] == 'complete')

    def test_stop_finalizes_partial_and_exports_only_detector_metadata(self):
        task_id = self.manager.start('run-1')
        self.assertTrue(self.entered.wait(2))
        self.assertFalse(self.manager.snapshot()['tasks'][0]['data_ready'])
        self.finish(task_id)
        task = self.manager.snapshot()['tasks'][0]
        self.assertTrue(task['data_ready'])
        self.assertTrue(task['files'][0]['ready'])
        manifest = json.loads(self.manager.file(task_id, 'manifest.json').read_text())
        self.assertEqual(manifest['segments'][0]['sha256'], hashlib.sha256(struct.pack('<ffff',1,0,-1,0)).hexdigest())
        self.assertNotIn('txHardware', json.dumps(manifest))
        self.assertNotIn('transmitter_A', json.dumps(task))
        self.assertGreater(task['wall_seconds'], 0)
        with self.assertRaises(ValueError):
            self.manager.file(task_id, '../../request.json')

    def test_rebuild_stops_generation_and_does_not_discard_history(self):
        task_id = self.manager.start('run-1')
        self.assertTrue(self.entered.wait(2))
        with self.assertRaisesRegex(ValueError, '收尾'):
            self.manager.prepare_new_run()
        self.finish(task_id)
        self.manager.prepare_new_run()
        self.entered.clear()
        second = self.manager.start('run-2')
        self.assertTrue(self.entered.wait(2))
        self.finish(second)
        self.assertNotEqual(task_id, second)
        self.assertEqual(len(self.manager.snapshot()['tasks']), 2)
        self.assertTrue(self.manager.file(task_id, 'manifest.json').is_file())

    def test_generation_failure_is_not_ready(self):
        self.manager._invoke = lambda *args: 1
        task_id = self.manager.start('run-fail')
        wait_for(lambda: self.manager.task(task_id)['phase'] == 'failed')
        self.assertFalse(self.manager.task(task_id)['data_ready'])

    def test_queued_stop_never_launches_matlab(self):
        self.manager.compute.acquire()
        try:
            task_id = self.manager.start('queued')
            self.manager.stop(task_id)
        finally:
            self.manager.compute.release()
        wait_for(lambda: self.manager.task(task_id)['phase'] == 'empty')
        self.assertFalse(self.entered.is_set())

    def test_analysis_failure_does_not_revoke_saved_data(self):
        def fail_analysis(task, entry, log):
            if entry == 'bds_capture_analyze':
                return 1
            return self.fake_matlab(task, entry, log)
        self.manager._invoke = fail_analysis
        task_id = self.manager.start('analysis-failure')
        self.assertTrue(self.entered.wait(2))
        self.manager.stop(task_id)
        wait_for(lambda: self.manager.task(task_id)['analysis'] == 'failed')
        self.assertTrue(self.manager.task(task_id)['data_ready'])
        self.assertTrue(self.manager.file(task_id, 'manifest.json').is_file())

    def test_history_survives_service_restart(self):
        task_id = self.manager.start('history')
        self.assertTrue(self.entered.wait(2))
        self.finish(task_id)
        self.manager.close()
        restored = CaptureManager(self.root / 'state')
        self.addCleanup(restored.close)
        self.assertTrue(restored.task(task_id)['data_ready'])
        self.assertTrue(restored.settings['enabled'])
        self.assertFalse(restored.busy())

    def test_other_scenarios_do_not_start_capture(self):
        app = Application(output_root=str(self.root / 'runs'))
        app.load(str(ROOT / 'scenarios/substation-em-attack.json'))
        app.wireless = self.manager
        try:
            node = next(d for d in app.config.devices if d.device_type == 'em_attack_source')
            result = app.submit_operation({'target_asset_id':node.device_id,'action_type':'start_attack'})
            self.assertEqual(result['status'], 'accepted')
            self.assertEqual(self.manager.tasks, [])
        finally:
            app.wireless = None
            app.close()

    def test_failed_capture_preflight_does_not_start_timing_attack(self):
        app = Application(output_root=str(self.root / 'runs'))
        app.load(SCENE)
        app.wireless = self.manager
        try:
            with patch.object(self.manager, '_preflight', side_effect=ValueError('MATLAB missing')):
                result = app.submit_operation({'target_asset_id':'time_attack_node','action_type':'start_attack'})
            self.assertEqual(result['status'], 'rejected')
            self.assertIn('MATLAB missing', result['reason'])
            self.assertFalse(app.engine.get_device('time_attack_node').emitting)
            self.assertFalse(self.manager.tasks)
        finally:
            app.wireless = None
            app.close()

    def test_corrupt_samples_rejected(self):
        task_id = self.manager.start('run-bad')
        self.assertTrue(self.entered.wait(2))
        original = self.manager._finalize
        def corrupt(task, result):
            (Path(task['directory']) / 'detector/segment_000001.iq.f32').write_bytes(b'bad')
            return original(task, result)
        self.manager._finalize = corrupt
        self.manager.stop(task_id)
        wait_for(lambda: self.manager.task(task_id)['phase'] == 'failed')
        self.assertFalse(self.manager.task(task_id)['data_ready'])

    def test_disabled_never_starts_matlab_and_settings_validate(self):
        self.manager.configure({'enabled':False})
        self.assertIsNone(self.manager.start('run'))
        with self.assertRaises(ValueError):
            self.manager.configure({'enabled':True,'output_directory':'relative','matlab':sys.executable})
        self.assertEqual(matlab_quote("C:/user's data"), "C:/user''s data")

    def test_pause_resume_do_not_stop_capture_but_stop_run_does(self):
        app = Application(output_root=str(self.root / 'runs'))
        app.load(SCENE)
        app.wireless = self.manager
        try:
            app.start()
            result = app.submit_operation({'target_asset_id':'time_attack_node','action_type':'start_attack'})
            self.assertEqual(result['status'], 'accepted')
            self.assertTrue(self.entered.wait(2))
            task_id = self.manager.tasks[0]['id']
            app.pause()
            self.assertFalse(Path(self.manager.task(task_id)['directory'], 'STOP').exists())
            app.start()
            app.stop()
            self.finish(task_id)
        finally:
            app.wireless = None
            app.close()

    def test_empty_capture_is_not_fabricated(self):
        def empty(task, entry, log):
            write_json(Path(task['directory'])/'generated.json', {'empty':True})
            return 0
        self.manager._invoke = empty
        task_id = self.manager.start('run')
        wait_for(lambda: self.manager.task(task_id)['phase'] == 'empty')
        self.assertFalse(self.manager.task(task_id)['data_ready'])
        self.assertFalse(self.manager.file(task_id, 'manifest.json').exists())


class CaptureHttpTests(unittest.TestCase):
    def test_api_default_disabled_and_no_arbitrary_file_access(self):
        with tempfile.TemporaryDirectory() as tmp:
            server = PresentationServer(output_root=tmp)
            try:
                self.assertFalse(server.handle_request('GET','/api/wireless')[1]['settings']['enabled'])
                status, body, _ = server.handle_request('POST','/api/wireless/settings',json.dumps({'enabled':True,'output_directory':'relative'}).encode())
                self.assertEqual(status,400)
                self.assertIn('error',body)
                self.assertEqual(server.handle_request('GET','/api/wireless/tasks/unknown/files/request.json')[0],404)
                self.assertEqual(server.handle_request('GET','/wireless-view.js')[0],200)
            finally:
                server.close()
