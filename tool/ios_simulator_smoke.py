"""Launch the real app in a task-owned CI simulator and preserve a screenshot."""
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import time

root = Path(__file__).resolve().parents[1]
output = root / 'build/ios-preview'
output.mkdir(parents=True, exist_ok=True)


def run(*args):
    return subprocess.check_output(list(args), text=True, timeout=240).strip()


if sys.platform != 'darwin' or not (os.environ.get('CI') or os.environ.get('CM_BUILD_ID')):
    raise SystemExit('This helper operates only on an isolated macOS CI runner.')

if '--cleanup' in sys.argv:
    path = output / 'simulator-id.txt'
    if path.exists():
        device = path.read_text().strip()
        assert re.fullmatch(r'[A-Fa-f0-9-]{36}', device)
        all_devices = json.loads(run('xcrun', 'simctl', 'list', 'devices', '-j'))['devices']
        item = next((d for ds in all_devices.values() for d in ds if d['udid'] == device), None)
        if item and item['name'].startswith('Nazzelha CI '):
            subprocess.run(['xcrun', 'simctl', 'shutdown', device], check=False)
            subprocess.run(['xcrun', 'simctl', 'delete', device], check=True)
    raise SystemExit(0)

available = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available', '-j'))['devices']
choices = [(runtime, device) for runtime, devices in available.items() if '.iOS-' in runtime
           for device in devices if device['name'].startswith('iPhone') and device.get('isAvailable', True)]
assert choices, 'No iOS simulator runtime is installed.'
choices.sort(key=lambda item: tuple(map(int, re.findall(r'\d+', item[0]))), reverse=True)
runtime, template = choices[0]
device_type = template.get('deviceTypeIdentifier')
if not device_type:
    types = json.loads(run('xcrun', 'simctl', 'list', 'devicetypes', '-j'))['devicetypes']
    device_type = next(d['identifier'] for d in types if d['name'] == template['name'])
name = 'Nazzelha CI ' + os.environ.get('GITHUB_RUN_ID', str(int(time.time())))
device = run('xcrun', 'simctl', 'create', name, device_type, runtime)
(output / 'simulator-id.txt').write_text(device)
run('xcrun', 'simctl', 'boot', device)
run('xcrun', 'simctl', 'bootstatus', device, '-b')
app = root / 'build/ios/iphonesimulator/Runner.app'
with (app / 'Info.plist').open('rb') as file:
    info = plistlib.load(file)
bundle = info['CFBundleIdentifier']
assert bundle == 'com.mohamedfooda.nazzelha'
run('xcrun', 'simctl', 'install', device, str(app))
launch = run('xcrun', 'simctl', 'launch', device, bundle)
pid = int(re.search(r':\s*(\d+)', launch)[1])
time.sleep(12)
os.kill(pid, 0)  # Simulator app processes are real host processes.
run('xcrun', 'simctl', 'io', device, 'screenshot', str(output / 'ios-app.png'))
report = dict(launched=True, process_alive=True, bundle=bundle,
              version=info['CFBundleShortVersionString'], minimum_ios=info['MinimumOSVersion'],
              runtime=runtime, device_type=device_type, screenshot='ios-app.png')
(output / 'launch-result.json').write_text(json.dumps(report, indent=2))
print(json.dumps(report))
