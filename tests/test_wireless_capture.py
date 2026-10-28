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
from sim2030.matlab_worker import MatlabWorker

ROOT = Path(__file__).resolve().parents[1]
SCENE = str(ROOT / 'scenarios/substation-time-attack.json')


def wait_for(predicate, timeout=5):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if predicate():
            return
        time.sleep(.01)
    raise AssertionError('Worker did not reach expected state')


class ReadyWorker:
    """Protocol double; does not run MATLAB or generate physical samples."""
    def __init__(self, directory, executable, source, role):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True)
        self.phase = 'ready'
        self.closed = False

    def status(self):
        return {'phase':self.phase, 'error':'worker crashed' if self.phase == 'failed' else ''}

    def close(self):
        self.closed = True
        self.phase = 'stopped'


class CaptureTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.manager = CaptureManager(self.root / 'state')
        self.addCleanup(self.manager.close)
        self.entered = threading.Event()
        self.manager.worker_factory = ReadyWorker
        self.manager.set_scene(True)
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

    def test_separate_plots_are_published_and_history_images_remain_accessible(self):
        task_id = self.manager.start('run-plots')
        self.assertTrue(self.entered.wait(2))
        self.finish(task_id)
        detector = Path(self.manager.task(task_id)['directory']) / 'detector'
        names = ['i_envelope.png', 'q_envelope.png', 'mean_psd.png',
                 'prn_search.png', 'correlation.png', 'overview.png', 'presence.png']
        server = PresentationServer.__new__(PresentationServer)
        server.capture = self.manager
        for name in names:
            (detector / name).write_bytes(b'published-image')
            self.assertEqual(self.manager.file(task_id, name).read_bytes(), b'published-image')
            status, body, headers = server.handle_request('GET', f'/api/wireless/tasks/{task_id}/files/{name}')
            self.assertEqual(status, 200)
            self.assertEqual(body['__bytes__'], b'published-image')
            self.assertEqual(headers['Content-Type'], 'image/png')
        for name in ('mean_psd.json','prn_search.json','correlation.json'):
            write_json(detector / name, {'kind':name})
            status, body, headers = server.handle_request('GET', f'/api/wireless/tasks/{task_id}/files/{name}')
            self.assertEqual(status, 200)
            self.assertEqual(headers['Content-Type'], 'application/json')
        self.assertEqual(self.manager.snapshot()['tasks'][0]['charts'],
                         ['mean_psd.json','prn_search.json','correlation.json'])
        (detector / 'mean_psd.png.partial.png').write_bytes(b'unfinished')
        self.assertEqual(server.handle_request('GET',
            f'/api/wireless/tasks/{task_id}/files/segment_000001.iq.f32')[0], 400)
        task = self.manager.snapshot()['tasks'][0]
        self.assertEqual(task['plots'], names)
        with self.assertRaises(ValueError):
            self.manager.file(task_id, 'mean_psd.png.partial.png')

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

    def test_start_before_ready_is_rejected_without_creating_task(self):
        self.manager.workers['generation'].phase = 'preparing'
        app = Application(output_root=str(self.root / 'runs'))
        app.load(SCENE)
        app.wireless = self.manager
        try:
            result = app.submit_operation({'target_asset_id':'time_attack_node','action_type':'start_attack'})
            self.assertEqual(result['status'], 'rejected')
            self.assertIn('相关装置启动中，请稍后', result['reason'])
            self.assertFalse(app.engine.get_device('time_attack_node').emitting)
            self.assertFalse(self.manager.tasks)
        finally:
            app.wireless = None
            app.close()

    def test_preparation_waits_for_scene_and_configuration_and_reuses_workers(self):
        self.manager.configure({'enabled':False})
        self.manager.set_scene(False)
        self.manager.configure({'enabled':True, 'output_directory':str(self.root / 'captures'), 'matlab':sys.executable})
        self.assertFalse(self.manager.workers)
        self.manager.set_scene(True)
        original = dict(self.manager.workers)
        self.assertEqual(self.manager.receiver()['detail'], '接收装置已就绪')
        self.assertEqual(self.manager.tasks, [])
        self.manager.set_scene(True)
        self.assertEqual(self.manager.workers, original)
        self.manager.configure({'enabled':False})
        self.assertTrue(all(worker.closed for worker in original.values()))

    def test_loading_timing_scene_prepares_saved_enabled_configuration(self):
        self.manager.configure({'enabled':False})
        self.manager.set_scene(False)
        self.manager.configure({'enabled':True,'output_directory':str(self.root/'captures'),'matlab':sys.executable})
        app = Application(output_root=str(self.root/'runs'))
        app.wireless = self.manager
        try:
            app.load(SCENE)
            self.assertEqual(self.manager.receiver()['phase'], 'ready')
            self.assertEqual(self.manager.tasks, [])
        finally:
            app.wireless = None
            app.close()

    def test_worker_crash_is_visible_and_resaving_reprepares(self):
        original = self.manager.workers['analysis']
        original.phase = 'failed'
        self.assertEqual(self.manager.snapshot()['receiver']['phase'], 'failed')
        with self.assertRaisesRegex(ValueError, 'worker crashed'):
            self.manager.start('failed')
        self.assertEqual(self.manager.tasks, [])
        self.manager.configure(dict(self.manager.settings))
        self.assertTrue(original.closed)
        self.assertIsNot(original, self.manager.workers['analysis'])
        self.assertEqual(self.manager.receiver()['phase'], 'ready')

    def test_first_closed_segment_is_analyzed_before_stop_exactly_once(self):
        analyzed = threading.Event()
        calls = []
        def concurrent(task, entry, log):
            folder = Path(task['directory'])
            if entry == 'bds_capture_analyze':
                self.assertFalse((folder / 'STOP').exists())
                calls.append(entry)
                write_json(folder / 'detector/analysis.json', {'overview':'saved','presence':'inconclusive'})
                analyzed.set()
                return 0
            (folder / 'detector/segment_000001.iq.f32').write_bytes(b'12345678')
            write_json(folder / 'first_segment.json', {'segments':{'fileName':'segment_000001.iq.f32',
                       'startSample':0,'sampleCount':1}})
            self.entered.set()
            while not (folder / 'STOP').exists():
                time.sleep(.01)
            # Normal final metadata is independent of the already published analysis.
            (folder / 'detector/segment_000001.iq.f32').unlink()
            return self.fake_matlab(task, entry, log)
        self.manager._invoke = concurrent
        task_id = self.manager.start('early')
        self.assertTrue(self.entered.wait(2))
        self.assertTrue(analyzed.wait(2))
        wait_for(lambda:self.manager.task(task_id)['analysis']=='complete')
        self.assertFalse(self.manager.task(task_id)['data_ready'])
        self.manager.stop(task_id)
        wait_for(lambda:self.manager.task(task_id)['phase']=='ready')
        self.assertEqual(calls, ['bds_capture_analyze'])
        request = json.loads((Path(self.manager.task(task_id)['directory'])/'analysis_request.json').read_text())
        self.assertTrue(request['metadataFile'].endswith('first_segment.json'))

    def test_partial_first_file_does_not_trigger_analysis(self):
        task_id = self.manager.start('partial')
        self.assertTrue(self.entered.wait(2))
        folder = Path(self.manager.task(task_id)['directory'])
        write_json(folder / 'first_segment.json', {'segments':{'fileName':'segment_000001.iq.f32',
                   'startSample':0,'sampleCount':2}})
        time.sleep(.2)
        self.assertEqual(self.manager.task(task_id)['analysis'], 'waiting')
        self.finish(task_id)

    def test_analysis_in_progress_blocks_next_attack_without_creating_task(self):
        gate = threading.Event()
        self.addCleanup(gate.set)
        def delayed(task, entry, log):
            if entry == 'bds_capture_analyze':
                gate.wait(2)
            return self.fake_matlab(task, entry, log)
        self.manager._invoke = delayed
        task_id = self.manager.start('first')
        self.assertTrue(self.entered.wait(2))
        self.manager.stop(task_id)
        wait_for(lambda:self.manager.task(task_id)['analysis']=='running')
        with self.assertRaisesRegex(ValueError, '分析尚未完成'):
            self.manager.start('second')
        self.assertEqual(len(self.manager.tasks), 1)
        gate.set()
        wait_for(lambda:self.manager.task(task_id)['analysis']=='complete')

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
                self.assertEqual(server.handle_request('GET','/wireless-charts.js')[0],200)
            finally:
                server.close()
