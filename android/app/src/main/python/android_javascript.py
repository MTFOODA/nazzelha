"""Local, packaged JavaScript engine for yt-dlp's YouTube challenge solver."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess

RUNTIME_MESSAGE = (
    'The built-in YouTube JavaScript engine could not start. '
    'Please restart the app or update to the latest version.'
)


class AndroidJavaScriptRuntime:
    def __init__(self):
        self.executable = None
        self.available = False
        self.diagnostics = dict(engine='quickjs-ng', available=False,
                                solver_available=False, error='Not initialized')

    def configure(self, native_lib_dir):
        path = Path(native_lib_dir) / 'libqjs.so'
        if self.available and self.executable == str(path):
            return dict(self.diagnostics)  # Packaged libraries cannot change within this app process.
        self.executable = None
        self.available = False
        self.diagnostics = dict(engine='quickjs-ng', available=False,
                                solver_available=False, executable=str(path))
        try:
            self.diagnostics['solver_available'] = importlib.util.find_spec('yt_dlp_ejs') is not None
            if not self.diagnostics['solver_available']:
                raise RuntimeError('The packaged yt-dlp-ejs solver is missing.')
            if not native_lib_dir or not path.is_file() or not os.access(path, os.X_OK):
                raise RuntimeError('The packaged QuickJS executable is missing or cannot execute.')
            result = subprocess.run([str(path), '-e', 'console.log(JSON.stringify({answer:6*7}))'],
                                    capture_output=True, text=True, timeout=8)
            if result.returncode != 0 or json.loads(result.stdout).get('answer') != 42:
                raise RuntimeError('QuickJS self-check failed: ' + result.stderr[:200])
            self.executable = str(path)
            self.available = True
            self.diagnostics.update(available=True, self_check=42)
        except Exception as error:
            self.diagnostics['error'] = str(error)[:300]
        return dict(self.diagnostics)

    def options(self):
        return {'js_runtimes': {'quickjs': {'path': self.executable}}} if self.available else {}

    def failure(self):
        return dict(success=False, error_code='LOCAL_RUNTIME_MISSING', error=RUNTIME_MESSAGE,
                    diagnostics={'youtube_javascript': dict(self.diagnostics)})
