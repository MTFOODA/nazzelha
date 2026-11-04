"""Bundle verified official Node for yt-dlp's JS solver in the Python runtime."""
import hashlib
import io
import tarfile
import urllib.request
from pathlib import Path

version = 'v24.20.0'
filename = f'node-{version}-linux-x64.tar.xz'
base = f'https://nodejs.org/dist/{version}/'
target = Path('python_backend/bin')
target.mkdir(parents=True, exist_ok=True)
with urllib.request.urlopen(base + 'SHASUMS256.txt', timeout=30) as response:
    checksums = response.read().decode()
expected = next(line.split()[0] for line in checksums.splitlines() if line.split()[-1] == filename)
with urllib.request.urlopen(base + filename, timeout=180) as response:
    data = response.read()
if hashlib.sha256(data).hexdigest() != expected:
    raise SystemExit('Official Node.js SHA256 verification failed.')
with tarfile.open(fileobj=io.BytesIO(data), mode='r:xz') as archive:
    for member, destination in ((f'node-{version}-linux-x64/bin/node', 'node'),
                                 (f'node-{version}-linux-x64/LICENSE', 'NODE-LICENSE.txt')):
        source = archive.extractfile(member)
        if source is None:
            raise SystemExit('Invalid official Node archive.')
        (target / destination).write_bytes(source.read())
(target / 'node').chmod(0o755)
print('Verified official Node.js runtime prepared for Vercel.')
