"""Assemble a portable Windows release from CMake INSTALL output."""
import argparse
import hashlib
import shutil
import zipfile
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--runner', default='build/windows_release/runner/Release')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
source = root / args.runner
engine = root / 'build/release_engine/nazzelha-engine'
stage = root / 'build/release_stage/Nazzelha'
if not (source / 'nazzelha.exe').is_file() or not (engine / 'nazzelha-engine.exe').is_file():
    raise SystemExit('Build the release runner and portable engine first.')
stage.mkdir(parents=True, exist_ok=True)
shutil.copytree(source, stage, dirs_exist_ok=True)
shutil.copytree(engine, stage / 'backend', dirs_exist_ok=True)
runtime_roots = list(Path('C:/Program Files/Microsoft Visual Studio').glob('**/Redist/MSVC/*/x64/Microsoft.VC*.CRT'))
if not runtime_roots:
    raise SystemExit('Visual C++ redistributable DLLs were not found.')
for dll in sorted(runtime_roots)[-1].glob('*.dll'):
    shutil.copy2(dll, stage / dll.name)
shutil.copy2(root / 'docs/RELEASE_README.txt', stage / 'README.txt')
licenses = stage / 'licenses'
licenses.mkdir(exist_ok=True)
for license_file in (root / 'assets/fonts').glob('*OFL*'):
    shutil.copy2(license_file, licenses / license_file.name)
shutil.copy2(root / 'docs/THIRD_PARTY.md', licenses / 'THIRD_PARTY.md')
shutil.copy2(root / 'docs/BRAND_ASSETS.md', licenses / 'BRAND_ASSETS.md')
shutil.copytree(root / 'docs/licenses', licenses, dirs_exist_ok=True)
destination = root / 'build/deliveries/Nazzelha-Windows-x64.zip'
destination.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(destination, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for file in sorted(stage.rglob('*')):
        if file.is_file():
            archive.write(file, file.relative_to(stage.parent))
print(destination.name, destination.stat().st_size, 'bytes', 'sha256=' + hashlib.file_digest(destination.open('rb'), 'sha256').hexdigest())
