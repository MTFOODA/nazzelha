"""Build a signed APK, also handling Flutter's stale dev-plugin registrant."""
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parent.parent
flutter = os.environ.get('FLUTTER_BIN') or shutil.which('flutter')
if not flutter:
    raise SystemExit('Put Flutter on PATH or set FLUTTER_BIN.')
subprocess.run([flutter, 'build', 'apk', '--release', '--config-only', '--no-pub'], cwd=root, check=True)
# Some SDK distributions leave development plugins in the Java registrant while
# Gradle correctly excludes their release dependencies. Remove only those
# generated registration blocks; never edit the SDK or include test plugins in
# production. A subsequent Flutter debug build regenerates its own registrant.
metadata = json.loads((root / '.flutter-plugins-dependencies').read_text())
development = {p['name'] for p in metadata['plugins']['android'] if p.get('dev_dependency')}
registrant = root / 'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java'
source = registrant.read_text(encoding='utf-8')
pattern = r'    try \{\n.*?    \} catch \(Exception e\) \{\n.*?\n    \}\n'
source, count = re.subn(pattern, lambda match: '' if any(
    f'plugin {name},' in match[0] for name in development) else match[0], source, flags=re.S)
registrant.write_text(source, encoding='utf-8')
print('Release registrant excludes development-only plugins.', flush=True)
wrapper = root / 'android/gradlew.bat'
subprocess.run([str(wrapper), 'assembleRelease',
    '-Ptarget-platform=android-arm,android-arm64,android-x64', '-Ptarget=lib/main.dart',
    '-Pdart-obfuscation=false', '-Ptrack-widget-creation=false', '-Ptree-shake-icons=true'],
    cwd=root / 'android', check=True)
apk = root / 'build/app/outputs/apk/release/app-release.apk'
destination = root / 'build/deliveries/Nazzelha-Android.apk'
destination.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(apk, destination)
print(destination.name, destination.stat().st_size, 'bytes')
