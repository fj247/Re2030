"""One persistent MATLAB process with an atomic, single-command file mailbox."""
from pathlib import Path
import json
import os
import subprocess
import sys
import threading
import time
import uuid


def _read(path):
    try:
        return json.loads(path.read_text(encoding='utf-8-sig'))
    except (OSError, ValueError):
        return None


def _write(path, value):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False), encoding='utf-8')
    os.replace(temporary, path)


class MatlabWorker:
    def __init__(self, directory, executable, source, role):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True)
        (self.directory / 'LEASE').touch()
        self.executable, self.source, self.role = executable, Path(source), role
        self.process = None
        self.error = ''
        self.started = time.monotonic()
        self.stopping = False
        self.busy = False
        self.lock = threading.Lock()
        self.boot = threading.Thread(target=self._launch, daemon=True)
        self.boot.start()

    def _launch(self):
        quote = lambda value: str(value).replace("'", "''")
        script = self.directory / 'launch.m'
        script.write_text(
            "try\n"
            f"addpath('{quote(self.source)}','-begin');\n"
            f"bds_capture_worker('{quote(self.directory)}','{self.role}');\n"
            "catch err\n"
            "fprintf(2,'%s\\n',getReport(err,'extended','hyperlinks','off'));\n"
            f"bds_capture_json('{quote(self.directory / 'startup_error.json')}',struct('message',err.message));\n"
            "exit(1);\nend\n", encoding='utf-8')
        args = [self.executable]
        if sys.platform == 'win32':
            args.append('-wait')
        args += ['-sd', str(self.source), '-logfile', str(self.directory / 'worker.log'),
                 '-batch', f"run('{quote(script)}');"]
        try:
            with (self.directory / 'launcher.log').open('wb') as log:
                self.process = subprocess.Popen(args, cwd=str(self.source), stdout=log, stderr=subprocess.STDOUT)
                # A stop may arrive while the native launcher is still starting.
                if self.stopping:
                    (self.directory / 'SHUTDOWN').touch()
                self.process.wait()
        except OSError as exc:
            self.error = str(exc)

    def status(self):
        failure = _read(self.directory / 'startup_error.json')
        if self.error or failure:
            return {'phase':'failed', 'error':self.error or failure.get('message', '启动失败')}
        if self.stopping:
            return {'phase':'stopped', 'error':''}
        if self.process is not None and self.process.poll() is not None:
            return {'phase':'failed', 'error':f'接收装置进程已退出（{self.process.returncode}），请重新保存设置以准备装置'}
        ready = (self.directory / 'ready.json').is_file() and self.process is not None
        if not ready and time.monotonic()-self.started > 300:
            self.error = '接收装置准备超时，请查看 ' + str(self.directory / 'worker.log')
            self.close()
            return {'phase':'failed', 'error':self.error}
        return {'phase':('busy' if self.busy else 'ready') if ready else 'preparing', 'error':''}

    def run(self, request, entry, log):
        with self.lock:
            if self.status()['phase'] != 'ready':
                raise ValueError('相关装置启动中，请稍后')
            self.busy = True
            job_id = uuid.uuid4().hex
            result_file = self.directory / (job_id + '.json')
            try:
                _write(self.directory / 'command.json', {'id':job_id, 'entry':entry,
                       'requestFile':str(request), 'logFile':str(log)})
                while True:
                    result = _read(result_file)
                    if result is not None:
                        result_file.unlink(missing_ok=True)
                        return result['exitCode']
                    if self.process.poll() is not None:
                        raise ValueError('接收装置进程意外退出，请查看 ' + str(self.directory / 'worker.log'))
                    time.sleep(.05)
            finally:
                self.busy = False

    def close(self):
        self.stopping = True
        (self.directory / 'SHUTDOWN').touch(exist_ok=True)
        # Cooperative exit only. No termination of a task that may be closing files.
