"""Build the portable Windows stdin/stdout download engine."""
import shutil
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
command = [sys.executable, '-m', 'PyInstaller', '--noconfirm', '--onedir', '--console',
    '--name', 'nazzelha-engine', '--distpath', 'build/release_engine',
    '--workpath', 'build/pyinstaller', '--specpath', 'build/pyinstaller-spec',
    '--paths', 'python_backend']
for package in ('yt_dlp', 'yt_dlp_ejs', 'curl_cffi', 'imageio_ffmpeg'):
    command += ['--collect-all', package]
subprocess.run(command + ['python_backend/main.py'], cwd=root, check=True)
node = shutil.which('node')
if not node:
    raise SystemExit('Node.js is required when packaging the standalone engine.')
tools = root / 'build/release_engine/nazzelha-engine/tools'
tools.mkdir(parents=True, exist_ok=True)
shutil.copy2(node, tools / 'node.exe')
license = Path(node).parent / 'LICENSE'
if license.exists():
    shutil.copy2(license, tools / 'NODE-LICENSE.txt')
python_license = Path(sys.base_prefix) / 'LICENSE.txt'
if python_license.exists():
    shutil.copy2(python_license, tools / 'PYTHON-LICENSE.txt')
print('Portable engine, FFmpeg and Node packaged successfully.')
