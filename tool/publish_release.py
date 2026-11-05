"""Publish only explicitly named Nazzelha release artifacts; never print credentials."""
import hashlib
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

root = Path(__file__).resolve().parents[1]
credential = subprocess.run(['git', 'credential', 'fill'], input='protocol=https\nhost=github.com\n\n',
    text=True, capture_output=True, check=True,
    env=dict(os.environ, GCM_INTERACTIVE='Never', GIT_TERMINAL_PROMPT='0'), timeout=20)
token = dict(line.split('=', 1) for line in credential.stdout.splitlines() if '=' in line).get('password')
if not token:
    raise SystemExit('No GitHub credential is available.')
headers = {'User-Agent': 'Nazzelha-release', 'Authorization': 'Bearer ' + token,
           'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'}
api = 'https://api.github.com/repos/MTFOODA/nazzelha'

def request(path, method='GET', data=None, content_type='application/json'):
    body = json.dumps(data).encode() if data is not None and content_type == 'application/json' else data
    req = urllib.request.Request(path if path.startswith('https://') else api + path,
        method=method, data=body, headers={**headers, 'Content-Type': content_type})
    with urllib.request.urlopen(req, timeout=900) as response:
        return json.load(response)

assets = [root / 'build/deliveries' / name for name in ('Nazzelha-Android.apk', 'Nazzelha-Windows-x64.zip', 'Nazzelha-Documentation.zip', 'Nazzelha-Walkthrough-AR.mp4')]
if any(not file.is_file() for file in assets):
    raise SystemExit('Release files are missing.')
checksums = root / 'build/deliveries/SHA256SUMS.txt'
checksums.write_text(''.join(hashlib.file_digest(file.open('rb'), 'sha256').hexdigest() + '  ' + file.name + '\n' for file in assets), encoding='utf-8')
assets.append(checksums)
commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
release = next((r for r in request('/releases') if r['tag_name'] == 'v1.1.3'), None)
notes = '''Nazzelha 1.1.3

- Fixed Android 7 startup by replacing API 26-only filesystem and process calls with compatible implementations.
- Corrected versioned splash resources and foreground-service receiver compatibility. Android release lint: zero errors.
- Fixed a release-only download failure: preserve the progress/cancellation callback methods called dynamically by Python when R8 optimizes the APK.
- Added an independent APK integrity gate covering the release certificate, signatures, ZIP CRCs, ABI machine types and 16 KB alignment, including packed FFmpeg libraries.
- Verified update and clean installation on Android 7 and Android 17 test images. A fresh public 1.1.2 download through the official website also installed and opened on the user's Xiaomi 15T Pro / HyperOS 3 / Android 17; the older local download was corrupt and failed its APK integrity check.
- Added an Arabic user manual, an annotated button guide and a captioned illustrated walkthrough (not a new live screen recording).
- Retains the website visit/download statistics, Windows/Android selection buttons, unified headers, playlist history and background Android downloads.

Android: universal APK for Android 7/API 24 and later, ARM64, ARMv7 and x86_64; version code 5. Same release certificate; signed releases can update in place.
Windows x64: extract the whole ZIP and open nazzelha.exe. The download engine, Python, Node and FFmpeg are bundled. Portable startup verified without developer tools on PATH. The executable is not Authenticode signed.
iPhone/iPad: web only; no native IPA.

Website: https://nazzelha.mohamed-fooda-mtf.workers.dev/ . Free hosting limits still apply; YouTube media requests can be rejected from Vercel's hosting network. Use the installed application for native background playlist downloading.

SHA-256 checksums are included in SHA256SUMS.txt. If an APK fails to install, download it again and compare its checksum; do not disable device security checks.
'''
if release is None:
    release = request('/releases', 'POST', dict(tag_name='v1.1.3', target_commitish=commit,
        name='Nazzelha 1.1.3', body=notes, draft=True, prerelease=False))
elif not release['draft']:
    raise SystemExit('This version is already published; refusing to replace public release files.')
else:
    release = request('/releases/' + str(release['id']), 'PATCH', dict(tag_name='v1.1.3', target_commitish=commit, body=notes))
def upload(file):
    existing = next((a for a in request('/releases/' + str(release['id']) + '/assets') if a['name'] == file.name), None)
    if existing:
        expected = 'sha256:' + hashlib.file_digest(file.open('rb'), 'sha256').hexdigest()
        if existing['size'] != file.stat().st_size or existing.get('digest') != expected:
            raise SystemExit('Existing draft asset does not match the verified local artifact: ' + file.name)
        print('Already uploaded:', file.name, flush=True)
        return
    url = release['upload_url'].split('{')[0] + '?name=' + urllib.parse.quote(file.name)
    uploaded = request(url, 'POST', file.read_bytes(), 'application/octet-stream')
    expected = 'sha256:' + hashlib.file_digest(file.open('rb'), 'sha256').hexdigest()
    if uploaded.get('digest') and uploaded['digest'] != expected:
        raise SystemExit('Asset digest mismatch.')
    if uploaded['size'] != file.stat().st_size:
        raise SystemExit('Asset size mismatch.')
    print('Uploaded:', file.name, uploaded['size'], 'bytes', flush=True)
from concurrent.futures import ThreadPoolExecutor
with ThreadPoolExecutor(max_workers=2) as pool:
    list(pool.map(upload, assets))
if '--publish' in sys.argv:
    release = request('/releases/' + str(release['id']), 'PATCH', dict(tag_name='v1.1.3', target_commitish=commit, draft=False, make_latest='true'))
    print('Published:', release['html_url'])
else:
    print('Draft assets ready; source commit:', commit)
