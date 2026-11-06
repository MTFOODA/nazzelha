"""Read-only live capture for a user-connected phone; tap Resume while running.

Reads only Nazzelha's process logs and basic app/OS versions. Does not clear
logs, install/uninstall apps, change settings, or read other apps' processes.
Reports stay in the ignored build directory and must not be publicly uploaded.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import threading
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = 'com.example.nazzelha'


def capture(max_seconds=180, prompt=None):
    sdk = (os.environ.get('ANDROID_SDK_ROOT') or os.environ.get('ANDROID_HOME')
           or str(Path(os.environ['LOCALAPPDATA']) / 'Android/sdk'))
    adb = Path(sdk) / 'platform-tools/adb.exe'
    if not adb.is_file():
        raise RuntimeError('Android SDK platform-tools/adb.exe was not found.')

    def read(*args):
        result = subprocess.run([str(adb), '-d', *args], capture_output=True,
                                timeout=40, check=True)
        return result.stdout.decode('utf-8', errors='replace').strip()

    # -d selects the USB phone, never a development emulator.
    pid = read('shell', 'pidof', PACKAGE).split()
    if not pid or not all(re.fullmatch(r'\d+', value) for value in pid):
        raise RuntimeError('Open Nazzelha, resume one failed video, then run this capture again.')
    destination = ROOT / 'build/android-playlist-issue'
    destination.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S-%f')
    log = destination / (stamp + '-logcat.txt')
    metadata = destination / (stamp + '-device.json')
    with log.open('wb') as output:
        process = subprocess.Popen(
            [str(adb), '-d', 'logcat', '-v', 'threadtime', '-T', '2000', '--pid=' + pid[0]],
            stdout=output, stderr=subprocess.PIPE)
        timer = threading.Timer(max_seconds, process.terminate)
        timer.daemon = True
        timer.start()
        try:
            print('LIVE CAPTURE STARTED. Keep this window open.', flush=True)
            print(prompt or 'On the phone: tap Resume on ONE failed playlist video.', flush=True)
            input('After the video succeeds or shows its error, press Enter HERE to save logs: ')
        finally:
            timer.cancel()
            if process.poll() is None:
                process.terminate()  # Stop only our read-only adb logcat client.
            try:
                _, errors = process.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                _, errors = process.communicate(timeout=10)
    package_info = read('shell', 'dumpsys', 'package', PACKAGE)
    version_lines = [line.strip() for line in package_info.splitlines()
                     if any(key in line for key in ('versionName=', 'versionCode=', 'primaryCpuAbi='))]
    report = dict(captured_at_utc=datetime.now(timezone.utc).isoformat(),
                  package=PACKAGE, app_version=version_lines,
                  android_release=read('shell', 'getprop', 'ro.build.version.release'),
                  android_sdk=read('shell', 'getprop', 'ro.build.version.sdk'),
                  model=read('shell', 'getprop', 'ro.product.model'),
                  process_filtered=True, device_settings_changed=False,
                  live_capture=True, log_bytes=log.stat().st_size,
                  capture_stderr=errors.decode('utf-8', errors='replace')[:1000])
    metadata.write_text(json.dumps(report, ensure_ascii=True, indent=2) + '\n', encoding='utf-8')
    print('Captured Nazzelha-only logs. No app data or settings were changed.')
    print(str(log))
    print(str(metadata))
    return {'log': str(log.relative_to(ROOT)), 'metadata': str(metadata.relative_to(ROOT))}


if __name__ == '__main__':
    try:
        capture()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print('Capture failed:', str(error).encode('ascii', errors='backslashreplace').decode())
        raise SystemExit(1)
