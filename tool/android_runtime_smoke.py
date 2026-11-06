"""CI-only app/engine startup acceptance on an isolated Android 7 emulator.

Does not claim a real YouTube download; physical-device acceptance is separate.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = 'com.example.nazzelha'


def smoke():
    if not os.environ.get('GITHUB_ACTIONS'):
        raise RuntimeError('This helper operates only on a task-owned GitHub Actions emulator.')
    output = ROOT / 'build/android-runtime-smoke'
    output.mkdir(parents=True, exist_ok=True)
    adb = shutil.which('adb')
    if not adb:
        raise RuntimeError('ADB is not on PATH.')

    def read(*args):
        return subprocess.check_output([adb, '-e', *args], timeout=90).decode('utf-8', errors='replace').strip()

    api = read('shell', 'getprop', 'ro.build.version.sdk')
    abi = read('shell', 'getprop', 'ro.product.cpu.abi')
    assert api == '24' and abi == 'x86_64', (api, abi)
    apk = ROOT / 'build/app/outputs/flutter-apk/app-debug.apk'
    assert 'Success' in read('install', '-r', str(apk))
    read('shell', 'am', 'start', '-W', '-n', PACKAGE + '/.MainActivity')
    deadline = time.monotonic() + 120
    initialized = None
    while time.monotonic() < deadline:
        logs = read('logcat', '-d', '-v', 'brief', '-s', 'NazzelhaPython:I', 'python.stderr:W', '*:S')
        (output / 'app-logcat.txt').write_text(logs + '\n', encoding='utf-8')
        for line in logs.splitlines():
            marker = 'Python initialize() returned: '
            if marker in line:
                initialized = json.loads(line.split(marker, 1)[1])
        if initialized is not None:
            break
        time.sleep(2)
    assert initialized and initialized['ready'], initialized
    diagnostics = initialized['diagnostics']
    javascript = diagnostics['youtube_javascript']
    assert javascript['available'] and javascript['solver_available'] and javascript['self_check'] == 42, javascript
    assert diagnostics['ffmpeg_run_ok'], diagnostics['ffmpeg_error']
    assert read('shell', 'pidof', PACKAGE), 'App exited after initialization.'
    time.sleep(3)
    screenshot = subprocess.check_output([adb, '-e', 'exec-out', 'screencap', '-p'], timeout=30)
    assert screenshot.startswith(b'\x89PNG\r\n\x1a\n')
    (output / 'android-7.png').write_bytes(screenshot)
    report = dict(passed=True, api=24, abi=abi, javascript_available=True,
                  solver_available=True, javascript_self_check=42, ffmpeg_run_ok=True,
                  real_youtube_media_download_tested=False,
                  package=PACKAGE, screenshot='android-7.png')
    (output / 'result.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report))


if __name__ == '__main__':
    smoke()
