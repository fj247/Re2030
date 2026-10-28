"""Local MATLAB capture orchestration. No waveform synthesis or RF transmission here."""
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import shutil
import subprocess
import sys
import threading
import time
import uuid

from sim2030.matlab_worker import MatlabWorker

MATLAB_SOURCE = Path(__file__).resolve().parents[1] / 'matlab' / 'beidou_b1i'
WRITING = {'queued', 'initializing', 'generating', 'stopping', 'finalizing'}
PLOTS = ('i_envelope.png', 'q_envelope.png', 'mean_psd.png', 'prn_search.png',
         'correlation.png', 'overview.png', 'presence.png')
CHARTS = ('mean_psd.json', 'prn_search.json', 'correlation.json')
FILES = {'manifest.json', 'analysis.json', *PLOTS, *CHARTS}


def read_json(path, default=None):
    try:
        return json.loads(Path(path).read_text(encoding='utf-8-sig'))
    except (OSError, ValueError):
        return default


def write_json(path, value):
    path = Path(path)
    tmp = path.with_suffix('.tmp')
    tmp.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')
    os.replace(tmp, path)


def utc():
    return datetime.now(timezone.utc).isoformat()


def matlab_quote(path):
    return str(path).replace("'", "''")


def default_matlab():
    found = shutil.which('matlab')
    if found:
        return found
    if os.name == 'nt':
        candidate = Path(os.environ.get('ProgramFiles', r'C:\Program Files')) / 'MATLAB/R2024a/bin/matlab.exe'
        if candidate.is_file():
            return str(candidate)
    return ''


class CaptureManager:
    def __init__(self, state_directory):
        self.directory = Path(state_directory).resolve()
        self.directory.mkdir(parents=True, exist_ok=True)
        self.lock = threading.RLock()
        self.compute = threading.Lock()  # one generation task; analysis uses a separate warm worker
        self.workers = {}
        self.worker_factory = MatlabWorker
        self.scene_active = False
        self.receiver_error = ''
        self.wake = threading.Event()
        self.analysis_queue = queue.Queue()
        self.settings = read_json(self.directory / 'settings.json', {})
        self.settings.setdefault('enabled', False)
        self.settings.setdefault('output_directory', '')
        self.settings.setdefault('matlab', default_matlab())
        self.tasks = read_json(self.directory / 'tasks.json', [])
        self.threads = []
        self.closed = False
        for task in self.tasks:
            if task['phase'] in WRITING or task['analysis'] in {'queued', 'running'}:
                # Never declare an orphan task successful. Request cooperative stop if MATLAB survived.
                Path(task['directory'], 'STOP').touch(exist_ok=True)
                task.update(phase='interrupted', analysis='interrupted', error='服务曾中断；保留文件，未确认任务完整结束')
        self._save()
        self.analyzer = threading.Thread(target=self._analysis_loop, daemon=True)
        self.analyzer.start()
        self.monitor = threading.Thread(target=self._monitor, daemon=True)
        self.monitor.start()

    def _save(self):
        write_json(self.directory / 'tasks.json', self.tasks)

    def configure(self, values):
        with self.lock:
            if self.busy() or self.analysis_busy():
                raise ValueError('上一轮生成、分析或文件收尾尚未结束，暂不能更改设置')
            enabled = values.get('enabled', False)
            if not isinstance(enabled, bool):
                raise ValueError('启用开关必须为布尔值')
            output = values.get('output_directory', '')
            executable = values.get('matlab', self.settings['matlab'])
            if not isinstance(output, str) or not isinstance(executable, str):
                raise ValueError('目录和 MATLAB 位置必须为文本')
            if enabled:
                self._preflight(output, executable)
            changed = self.settings != {'enabled': enabled, 'output_directory': output, 'matlab': executable}
            if changed or any(w.status()['phase'] == 'failed' for w in self.workers.values()):
                self._release_workers()
            self.receiver_error = ''
            self.settings = {'enabled': enabled, 'output_directory': output, 'matlab': executable}
            write_json(self.directory / 'settings.json', self.settings)
            self._prepare_receiver()
            return self.snapshot()

    def set_scene(self, active):
        with self.lock:
            self.scene_active = bool(active)
            self._prepare_receiver()

    def _release_workers(self):
        for worker in self.workers.values():
            worker.close()
        self.workers = {}

    def _prepare_receiver(self):
        if self.closed or not self.scene_active or not self.settings['enabled'] or self.workers:
            return
        try:
            executable = self._preflight(self.settings['output_directory'], self.settings['matlab'])
            session = self.directory / 'workers' / uuid.uuid4().hex
            self.receiver_error = ''
            for role in ('generation', 'analysis'):
                self.workers[role] = self.worker_factory(session / role, executable, MATLAB_SOURCE, role)
        except (ValueError, OSError) as exc:
            self.receiver_error = str(exc)
            self._release_workers()

    def analysis_busy(self):
        return any(t['analysis'] in {'queued', 'running'} for t in self.tasks)

    def receiver(self):
        if not self.settings['enabled']:
            return {'phase':'disabled', 'detail':'无线采集未启用'}
        if self.receiver_error:
            return {'phase':'failed', 'detail':self.receiver_error}
        if not self.workers:
            return {'phase':'inactive', 'detail':'加载授时攻击场景并保存有效设置后准备接收装置'}
        states = [worker.status() for worker in self.workers.values()]
        failure = next((state for state in states if state['phase'] == 'failed'), None)
        if failure:
            return {'phase':'failed', 'detail':failure['error']}
        if any(state['phase'] in {'preparing', 'stopped'} for state in states):
            return {'phase':'preparing', 'detail':'接收装置准备中'}
        if self.busy() or self.analysis_busy() or any(state['phase'] == 'busy' for state in states):
            return {'phase':'busy', 'detail':'接收装置处理中'}
        return {'phase':'ready', 'detail':'接收装置已就绪'}

    def _queue_analysis(self, task, metadata=None):
        if task['analysis'] != 'waiting':
            return
        folder = Path(task['directory'])
        if metadata:
            write_json(folder / 'analysis_request.json', {'taskDirectory':str(folder), 'metadataFile':str(metadata)})
        task['analysis'] = 'queued'
        self._save()
        self.analysis_queue.put(task)

    def _monitor(self):
        last_lease = 0
        while not self.wake.wait(.1):
            with self.lock:
                renew = time.monotonic()-last_lease > 2
                if renew:
                    last_lease = time.monotonic()
                for worker in self.workers.values():
                    # Worker exits if the service disappears and this lease becomes stale.
                    if renew:
                        try:
                            Path(worker.directory, 'LEASE').touch(exist_ok=True)
                        except OSError as exc:
                            self.receiver_error = '接收装置续期失败：' + str(exc)
                for task in self.tasks:
                    if task['phase'] not in WRITING or task['analysis'] != 'waiting':
                        continue
                    metadata = Path(task['directory'], 'first_segment.json')
                    meta = read_json(metadata)
                    if not meta:
                        continue
                    try:
                        row = meta['segments']
                        if isinstance(row, list):
                            row = row[0]
                        path = self._file(task, row['fileName'])
                        if row['startSample'] == 0 and row['sampleCount'] > 0 and path.stat().st_size == row['sampleCount'] * 8:
                            self._queue_analysis(task, metadata)
                    except (KeyError, ValueError, OSError, IndexError, TypeError):
                        continue

    def _preflight(self, output, executable):
        if not output or not Path(output).is_absolute():
            raise ValueError('请选择绝对保存目录')
        root = Path(output)
        root.mkdir(parents=True, exist_ok=True)
        probe = root / ('.capture-write-check-' + uuid.uuid4().hex)
        try:
            probe.write_bytes(b'')
        finally:
            probe.unlink(missing_ok=True)
        resolved = shutil.which(executable) if executable else None
        if not resolved or not Path(resolved).is_file():
            raise ValueError('未找到 MATLAB，请填写 R2024a 的 matlab.exe 完整路径')
        if shutil.disk_usage(root).free < 512 * 1024**2:
            raise ValueError('保存目录至少需要 512 MiB 可用空间')
        return str(Path(resolved).resolve())

    def busy(self):
        return any(t['phase'] in WRITING for t in self.tasks)

    def prepare_new_run(self):
        with self.lock:
            if self.busy():
                self.stop()
                raise ValueError('已请求停止上一轮采集，文件收尾完成后请再次加载运行；图表分析无需等待')

    def start(self, run_id):
        with self.lock:
            if not self.settings['enabled']:
                return None
            if self.closed or self.busy():
                raise ValueError('上一轮采集尚未完成收尾')
            executable = self._preflight(self.settings['output_directory'], self.settings['matlab'])
            self._prepare_receiver()
            receiver = self.receiver()
            if receiver['phase'] == 'failed':
                raise ValueError(receiver['detail'])
            if receiver['phase'] == 'busy':
                raise ValueError('上一轮采集或分析尚未完成，请稍后')
            if receiver['phase'] != 'ready':
                raise ValueError('相关装置启动中，请稍后')
            task_id = uuid.uuid4().hex
            folder = Path(self.settings['output_directory']).resolve() / ('capture_' + task_id)
            (folder / 'detector').mkdir(parents=True)
            task = {'id': task_id, 'run_id': run_id, 'directory': str(folder), 'matlab': executable,
                    'created_at': utc(), 'started_monotonic': time.monotonic(), 'phase': 'queued',
                    'analysis': 'waiting', 'error': '', 'stop_requested_at': None, 'data_ready': False}
            write_json(folder / 'request.json', {'taskDirectory': str(folder),
                       'maxBytes': min(2 * 1024**3, shutil.disk_usage(folder).free - 256 * 1024**2),
                       'serviceLeaseFile': str(self.workers['generation'].directory / 'LEASE')})
            self.tasks.append(task)
            self._save()
            thread = threading.Thread(target=self._generate, args=(task,), daemon=True)
            self.threads.append(thread)
            thread.start()
            return task_id

    def stop(self, task_id=None):
        with self.lock:
            for task in self.tasks:
                if task['phase'] in WRITING and (task_id is None or task['id'] == task_id):
                    Path(task['directory'], 'STOP').touch(exist_ok=True)
                    if not task['stop_requested_at']:
                        task.update(stop_requested_at=utc(), wall_seconds=time.monotonic()-task['started_monotonic'])
                    task['phase'] = 'stopping'
            self._save()

    def _invoke(self, task, entry, log_name):
        role = {'bds_capture_entry':'generation', 'bds_capture_analyze':'analysis'}.get(entry)
        if role is None:
            raise ValueError('未知 MATLAB 接入入口')
        folder = Path(task['directory'])
        request = folder / ('analysis_request.json' if role == 'analysis' and (folder / 'analysis_request.json').exists() else 'request.json')
        code = self.workers[role].run(request, entry, folder / log_name)
        with self.lock:
            task[role + '_exit_code'] = code
            if role == 'generation':
                task['exit_code'] = code
            self._save()
        return code

    def _generate(self, task):
        try:
            with self.compute:
                with self.lock:
                    if Path(task['directory'], 'STOP').exists():
                        task.update(phase='empty', analysis='not_needed', finished_at=utc())
                        self._save()
                        return
                    task['phase'] = 'initializing'
                    self._save()
                exit_code = self._invoke(task, 'bds_capture_entry', 'generation.log')
            result = read_json(Path(task['directory'], 'generated.json'))
            if exit_code != 0 or not result:
                error = read_json(Path(task['directory'], 'generation_error.json'), {}) or read_json(Path(task['directory'], 'generation_launch_error.json'), {})
                raise ValueError(error.get('message') or f'MATLAB 退出码 {exit_code}，未获得完整生成结果；请查看 generation.log 和接收装置 worker.log')
            with self.lock:
                task['phase'] = 'finalizing'
                self._save()
            if result.get('empty'):
                with self.lock:
                    task.update(phase='empty', analysis='not_needed', finished_at=utc())
                    self._save()
                return
            manifest = self._finalize(task, result)
            with self.lock:
                task.update(phase='ready', data_ready=True, finished_at=utc(),
                            signal_seconds=manifest['signal_seconds'], sample_count=manifest['sample_count'])
                if not task['stop_requested_at']:
                    task['wall_seconds'] = time.monotonic()-task['started_monotonic']
                self._save()
                self._queue_analysis(task)
        except Exception as exc:
            with self.lock:
                task.update(phase='failed', error=str(exc), finished_at=utc())
                if task['analysis'] == 'waiting':
                    task['analysis'] = 'not_started'
                self._save()

    def _finalize(self, task, result):
        root = Path(task['directory']).resolve()
        metadata = Path(result['metadataFile']).resolve()
        if not metadata.is_relative_to(root / 'private'):
            raise ValueError('MATLAB 元数据目录异常')
        meta = read_json(metadata)
        if not meta or not meta.get('verification', {}).get('structuralPassed'):
            raise ValueError('MATLAB 文件结构校验未通过')
        segments = meta['segments']
        if isinstance(segments, dict):
            segments = [segments]
        index = []
        start = 0
        for row in segments:
            name = Path(row['fileName'].replace('\\', '/')).name
            path = self._file(task, name)
            if row['startSample'] != start or row['sampleCount'] <= 0 or path.stat().st_size != row['sampleCount'] * 8:
                raise ValueError('分片不连续或文件大小不符')
            digest = hashlib.sha256()
            with path.open('rb') as stream:
                for block in iter(lambda: stream.read(1024**2), b''):
                    digest.update(block)
            index.append({'name': name, 'start_sample': start, 'sample_count': row['sampleCount'],
                          'bytes': path.stat().st_size, 'sha256': digest.hexdigest(), 'ready': True})
            start += row['sampleCount']
        if start != meta['numberComplexSamples']:
            raise ValueError('总样本数与分片不一致')
        manifest = {'schema': 'detector-iq-v1', 'sample_rate_hz': meta['sampleRateHz'],
                    'format': 'little-endian float32 I0,Q0,I1,Q1,...', 'sample_count': start,
                    'signal_seconds': start / meta['sampleRateHz'], 'segments': index,
                    'capture_requested_at': task['created_at'], 'stop_requested_at': task['stop_requested_at'],
                    'data_ready': True}
        write_json(root / 'detector' / 'manifest.json', manifest)
        return manifest

    def _analysis_loop(self):
        while True:
            task = self.analysis_queue.get()
            if task is None:
                return
            try:
                with self.lock:
                    task['analysis'] = 'running'
                    self._save()
                code = self._invoke(task, 'bds_capture_analyze', 'analysis.log')
                report = read_json(Path(task['directory'], 'detector/analysis.json'))
                if code != 0 or not report:
                    raise ValueError('图表分析未正常完成，请查看分析日志')
                with self.lock:
                    task['analysis'] = 'complete' if report.get('overview') == 'saved' and report.get('presence') != 'failed' else 'partial'
                    self._save()
            except Exception as exc:
                with self.lock:
                    task.update(analysis='failed', analysis_error=str(exc))
                    self._save()
            finally:
                self.analysis_queue.task_done()

    def task(self, task_id):
        return next((t for t in self.tasks if t['id'] == task_id), None)

    def _file(self, task, name):
        if name not in FILES and not re.fullmatch(r'segment_\d{6}\.iq\.f32', name):
            raise ValueError('不允许访问该文件')
        root = Path(task['directory'], 'detector').resolve()
        path = (root / name).resolve()
        if path.parent != root:
            raise ValueError('文件必须位于本轮检测目录')
        return path

    def file(self, task_id, name):
        task = self.task(task_id)
        if not task:
            raise ValueError('任务不存在')
        return self._file(task, name)

    def snapshot(self):
        with self.lock:
            tasks = []
            for source in reversed(self.tasks):
                folder = Path(source['directory'])
                progress = read_json(folder / 'progress.json', {})
                phase = source['phase']
                if phase == 'initializing' and progress.get('phase') in {'generating', 'finalizing'}:
                    phase = progress['phase']
                files = []
                for path in sorted((folder / 'detector').glob('segment_*.f32*')):
                    try:
                        size = path.stat().st_size
                    except FileNotFoundError:
                        continue
                    files.append({'name': path.name, 'bytes': size,
                                  'ready': source['data_ready'] and not path.name.endswith('.partial')})
                tasks.append({k: source.get(k) for k in ('id', 'run_id', 'created_at', 'finished_at', 'stop_requested_at', 'data_ready', 'analysis', 'error', 'analysis_error', 'wall_seconds')} | {
                    'phase': phase, 'directory': str(folder / 'detector'), 'files': files,
                    'stage_detail': ('接收装置已接受采集任务；' + {'initializing':'初始化／首块计算尚未完成', 'generating':'正在生成样本', 'finalizing':'正在关闭文件和校验'}.get(progress.get('phase'), '尚未报告首块样本')) if (folder / 'generation_entered.json').is_file() else ('等待接收装置接受采集任务' if source['phase'] in WRITING else '本轮执行记录不可用'),
                    'exit_code': source.get('exit_code'),
                    'wall_seconds': source.get('wall_seconds', time.monotonic()-source['started_monotonic'] if source['phase'] in WRITING else None),
                    'bytes': sum(f['bytes'] for f in files),
                    'sample_count': source.get('sample_count', progress.get('sampleCount', 0)),
                    'signal_seconds': source.get('signal_seconds', progress.get('signalSeconds', 0)),
                    'limit': read_json(folder / 'limit.json'),
                    'plots': [name for name in PLOTS if (folder / 'detector' / name).is_file()],
                    'charts': [name for name in CHARTS if (folder / 'detector' / name).is_file()],
                    'analysis_report': read_json(folder / 'detector/analysis.json')})
            return {'settings': dict(self.settings), 'tasks': tasks, 'busy': self.busy(), 'receiver': self.receiver(),
                    'storage_limit_bytes': 2 * 1024**3}

    def pick_directory(self):
        if os.name != 'nt':
            raise ValueError('本机目录选择窗口仅支持 Windows；可直接输入绝对路径')
        script = "import tkinter as t;from tkinter import filedialog;r=t.Tk();r.withdraw();print(filedialog.askdirectory(title='选择检测数据保存目录'));r.destroy()"
        try:
            result = subprocess.run([sys.executable, '-X', 'utf8', '-c', script], capture_output=True, encoding='utf-8', timeout=120)
        except subprocess.TimeoutExpired as exc:
            raise ValueError('目录选择超时，请重试或直接输入路径') from exc
        if result.returncode:
            raise ValueError('无法打开本机目录选择窗口，请直接输入绝对路径')
        return result.stdout.strip()

    def open_directory(self, task_id):
        task = self.task(task_id)
        if not task or os.name != 'nt':
            raise ValueError('仅支持打开本机 Windows 上已知任务的目录')
        os.startfile(str(Path(task['directory'], 'detector')))  # user-clicked, known directory only

    def close(self):
        if self.closed:
            return
        self.closed = True
        self.stop()
        for thread in self.threads:
            thread.join(timeout=30)
        self.analysis_queue.put(None)
        self.analyzer.join(timeout=30)
        self.wake.set()
        self.monitor.join(timeout=2)
        with self.lock:
            self._release_workers()
