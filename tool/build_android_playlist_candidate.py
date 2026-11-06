"""Manually build and verify a candidate APK; never install or publish it.

Uses the installed Flutter/Android toolchains and existing release signing.
The agent can inspect the saved log when direct tool execution is unavailable.
"""
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

from prepare_android_javascript import ARCHITECTURES, validate_elf

ROOT = Path(__file__).resolve().parents[1]


def build():
    output = ROOT / 'build/android-playlist-candidate'
    output.mkdir(parents=True, exist_ok=True)
    flutter = os.environ.get('FLUTTER_BIN') or shutil.which('flutter')
    if not flutter:
        for line in (ROOT / 'android/local.properties').read_text(encoding='utf-8').splitlines():
            if line.startswith('flutter.sdk='):
                sdk = line.split('=', 1)[1].replace('\\\\', '\\').replace('\\:', ':')
                flutter = str(Path(sdk) / 'bin/flutter.bat')
                break
    if not flutter or not Path(flutter).is_file():
        raise RuntimeError('Set FLUTTER_BIN to the installed flutter.bat path.')
    environment = dict(os.environ, FLUTTER_BIN=flutter, PYTHONUTF8='1')
    steps = []
    status = dict(passed=False, installed_on_phone=False, published=False, steps=steps)
    status_path = output / 'result.json'
    status_path.write_text(json.dumps(status, indent=2), encoding='utf-8')
    with (output / 'build.log').open('wb') as log:
        def run(label, args):
            header = ('\n### ' + label + '\n').encode()
            log.write(header)
            log.flush()
            print(label, flush=True)
            with subprocess.Popen([str(a) for a in args], cwd=ROOT, env=environment,
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT) as process:
                for line in process.stdout:
                    log.write(line)
                    log.flush()
                    sys.stdout.buffer.write(line)
                    sys.stdout.buffer.flush()
                code = process.wait()
            steps.append(dict(step=label, exit_code=code))
            status_path.write_text(json.dumps(status, indent=2), encoding='utf-8')
            if code:
                raise RuntimeError(label + ' failed; see build/android-playlist-candidate/build.log')

        run('Resolve Flutter packages', [flutter, 'pub', 'get', '--no-example'])
        run('Flutter analyzer', [flutter, 'analyze'])
        run('Flutter regression tests', [flutter, 'test', 'test'])
        run('Build signed candidate with Android JavaScript runtime',
            [sys.executable, ROOT / 'tool/build_android_release.py'])
    apk = ROOT / 'build/deliveries/Nazzelha-Android.apk'
    with zipfile.ZipFile(apk) as archive:
        if archive.testzip() is not None:
            raise RuntimeError('APK archive integrity verification failed.')
        for abi, machine in ARCHITECTURES.items():
            validate_elf(archive.read('lib/' + abi + '/libqjs.so'), machine)
        with zipfile.ZipFile(io.BytesIO(archive.read('assets/chaquopy/requirements-common.imy'))) as packages:
            scripts = [n for n in packages.namelist() if n.startswith('yt_dlp_ejs/') and n.endswith('.js')]
            if not scripts:
                raise RuntimeError('The EJS challenge solver scripts are missing from the APK.')
    status.update(passed=True, apk=str(apk.relative_to(ROOT)), bytes=apk.stat().st_size,
                  sha256=hashlib.sha256(apk.read_bytes()).hexdigest(),
                  runtime_abis=list(ARCHITECTURES), page_size_verified=16384,
                  ejs_scripts_present=True)
    status_path.write_text(json.dumps(status, indent=2) + '\n', encoding='utf-8')
    print('CANDIDATE BUILD PASSED. Nothing was installed or published.', flush=True)
    print(str(apk), flush=True)


if __name__ == '__main__':
    try:
        build()
    except (OSError, RuntimeError, subprocess.SubprocessError, ValueError, KeyError) as error:
        print('BUILD FAILED:', str(error).encode('ascii', errors='backslashreplace').decode(), flush=True)
        raise SystemExit(1)
