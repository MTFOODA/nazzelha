"""Manually install the verified candidate as an update, then capture its test.

Never uninstall, clear app data, change device settings or publish a release.
Refuses mismatched signing identities before attempting the update.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

from capture_android_playlist_issue import capture
from verify_android_release import CERTIFICATE

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = 'com.example.nazzelha'


def install_and_capture():
    output = ROOT / 'build/android-playlist-candidate'
    status_path = output / 'install-result.json'
    candidate = json.loads((output / 'result.json').read_text(encoding='utf-8'))
    if not candidate['passed']:
        raise RuntimeError('The candidate build has not passed. Nothing will be installed.')
    apk = ROOT / 'build/deliveries/Nazzelha-Android.apk'
    if hashlib.sha256(apk.read_bytes()).hexdigest() != candidate['sha256']:
        raise RuntimeError('APK changed after verification. Nothing will be installed.')
    report = dict(installed=False, app_data_cleared=False, source_sha256=candidate['sha256'])
    status_path.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    sdk = Path(os.environ.get('ANDROID_SDK_ROOT') or os.environ.get('ANDROID_HOME')
               or Path(os.environ['LOCALAPPDATA']) / 'Android/sdk')
    adb = sdk / 'platform-tools/adb.exe'

    def read(*args, timeout=90):
        result = subprocess.run([str(adb), '-d', *args], capture_output=True, timeout=timeout)
        if result.returncode:
            message = (result.stdout + result.stderr).decode('utf-8', errors='replace')
            raise RuntimeError(message[:1500])
        return result.stdout.decode('utf-8', errors='replace').strip()

    paths = read('shell', 'pm', 'path', PACKAGE).splitlines()
    remote = next((line[len('package:'):] for line in paths if line.endswith('/base.apk')), None)
    if not remote or not re.fullmatch(r'/data/app/[A-Za-z0-9_~./+=-]+/base\.apk', remote):
        raise RuntimeError('Could not identify the currently installed Nazzelha APK. Nothing was changed.')
    original = output / 'installed-before.apk'
    read('pull', remote, str(original))
    versions = [p for p in (sdk / 'build-tools').iterdir() if (p / 'apksigner.bat').is_file()]
    tools = max(versions, key=lambda p: tuple(int(n) for n in re.findall(r'\d+', p.name)))
    signer = subprocess.run([str(tools / 'apksigner.bat'), 'verify', '--print-certs', str(original)],
                            check=True, capture_output=True, text=True)
    match = re.search(r'certificate SHA-256 digest: ([a-f0-9]+)', signer.stdout)
    if not match or match[1] != CERTIFICATE:
        raise RuntimeError('Installed app has a different signing key. Refusing to replace or uninstall it.')
    print('Signing identity matches. Updating without clearing data...', flush=True)
    result = read('install', '-r', str(apk), timeout=180)
    if 'Success' not in result:
        raise RuntimeError('Android did not confirm a successful update: ' + result)
    report.update(installed=True, signing_certificate_sha256=CERTIFICATE)
    status_path.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('UPDATE INSTALLED. Opening Nazzelha...', flush=True)
    read('shell', 'am', 'start', '-W', '-n', PACKAGE + '/.MainActivity')
    print('Test the SAME playlist now. Capture will save only Nazzelha logs.', flush=True)
    report['capture'] = capture(max_seconds=1200,
        prompt='On the phone: Resume the SAME six-video playlist. You may put the app in the background. '
               'Press Enter here only after it finishes or fails.')
    status_path.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    try:
        install_and_capture()
    except (OSError, RuntimeError, subprocess.SubprocessError, ValueError, KeyError) as error:
        print('UPDATE STOPPED:', str(error).encode('ascii', errors='backslashreplace').decode(), flush=True)
        print('Nothing was uninstalled and app data was not cleared.', flush=True)
        raise SystemExit(1)
