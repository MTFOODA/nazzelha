"""Exercise actual browser Blob/ZIP behavior using a fresh headless Edge profile."""
import os
import shutil
import subprocess
import threading
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

root = Path(__file__).resolve().parent.parent
site = root / 'build/browser_transfer_test'
site.mkdir(parents=True, exist_ok=True)
dart = os.environ.get('DART_BIN') or shutil.which('dart')
if not dart:
    raise SystemExit('Put Dart on PATH or set DART_BIN.')
subprocess.run([dart, 'compile', 'js', '-O2', '-o', str(site / 'transfer_test.js'),
                str(root / 'test_driver/browser_transfer_app.dart')], cwd=root, check=True)
(site / 'index.html').write_text('<!doctype html><meta charset="utf-8"><title>Browser transfer test</title><body>Running<script defer src="transfer_test.js"></script>', encoding='utf-8')
edge = Path(os.environ.get('EDGE_EXECUTABLE', 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'))
profile = root / 'build/edge-transfer-pure-test-profile'
done = threading.Event()
results = []

class Handler(SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass
    def do_POST(self):
        if self.path != '/result':
            self.send_error(404)
            return
        results.append(self.rfile.read(min(int(self.headers.get('Content-Length', 0)), 10000)).decode())
        self.send_response(200)
        self.end_headers()
        done.set()

server = ThreadingHTTPServer(('127.0.0.1', 8098), partial(Handler, directory=str(site)))
threading.Thread(target=server.serve_forever, daemon=True).start()
process = subprocess.Popen([str(edge), '--headless', '--disable-gpu', '--no-proxy-server',
    '--no-first-run', '--disable-extensions', '--user-data-dir=' + str(profile),
    'http://127.0.0.1:8098/'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    if not done.wait(90):
        raise SystemExit('FAIL: Edge did not report a result within 90 seconds.')
    print(results[0])
    if not results[0].startswith('PASS'):
        raise SystemExit(1)
finally:
    server.shutdown()
    if process.poll() is None:
        process.terminate()
        process.wait(timeout=10)
