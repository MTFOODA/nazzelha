"""Bundle the small, supported QuickJS-NG runtime for Vercel's size limit."""
import hashlib
import urllib.request
from pathlib import Path

version = 'v0.18.0'
url = f'https://github.com/quickjs-ng/quickjs/releases/download/{version}/qjs-linux-x86_64'
expected = '85ded23b9fabe8c1644fc40a8d2bbdd71157affcbd807359c618cc717ee24d7d'
target = Path('python_backend/bin')
target.mkdir(parents=True, exist_ok=True)
with urllib.request.urlopen(url, timeout=90) as response:
    data = response.read()
if hashlib.sha256(data).hexdigest() != expected:
    raise SystemExit('Official QuickJS-NG SHA256 verification failed.')
# These two files are artifacts from the previous Vercel packager only.
for legacy in ('node', 'NODE-LICENSE.txt'):
    (target / legacy).unlink(missing_ok=True)
(target / 'qjs').write_bytes(data)
(target / 'qjs').chmod(0o755)
with urllib.request.urlopen(f'https://raw.githubusercontent.com/quickjs-ng/quickjs/{version}/LICENSE', timeout=30) as response:
    (target / 'QUICKJS-LICENSE.txt').write_bytes(response.read())
print('Verified QuickJS-NG runtime prepared for Vercel:', len(data), 'bytes.')
