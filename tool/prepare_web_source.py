"""Export committed web sources, excluding local credentials and build caches."""
import io
import json
import subprocess
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
destination = root / 'build/web_source' / commit[:12]
destination.mkdir(parents=True, exist_ok=True)
paths = ['api', 'lib', 'assets', 'web', 'python_backend', 'tool', 'pubspec.yaml',
         'pubspec.lock', 'package.json', 'package-lock.json', 'vercel.json',
         'requirements.txt', '.python-version', '.vercelignore', '.gitignore']
archive = subprocess.check_output(['git', 'archive', '--format=zip', 'HEAD', '--', *paths], cwd=root)
with zipfile.ZipFile(io.BytesIO(archive)) as source:
    for item in source.infolist():
        target = (destination / item.filename).resolve()
        if not target.is_relative_to(destination.resolve()):
            raise SystemExit('Invalid archive path.')
    source.extractall(destination)
reference = json.loads((root / '.vercel/project.json').read_text())
link = destination / '.vercel'
link.mkdir(exist_ok=True)
(link / 'project.json').write_text(json.dumps({key: reference[key] for key in
    ('projectId', 'orgId', 'projectName') if key in reference}), encoding='utf-8')
print(destination)
