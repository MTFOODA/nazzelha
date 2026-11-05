#!/usr/bin/env bash
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'iOS builds require a macOS runner with Xcode.' >&2
  exit 1
fi
mkdir -p build/deliveries build/ios-preview
flutter --version
xcodebuild -version
flutter pub get
flutter analyze
flutter test test
flutter build ios --release --no-codesign
mkdir -p build/ios-preview/Payload
ditto build/ios/iphoneos/Runner.app build/ios-preview/Payload/Runner.app
ditto -c -k --keepParent build/ios-preview/Payload build/deliveries/Nazzelha-iOS-Unsigned.ipa
# The archive above is an unsigned device build, never a simulator IPA.
flutter build ios --simulator --debug
ditto -c -k --keepParent build/ios/iphonesimulator/Runner.app build/deliveries/Nazzelha-iOS-Simulator.zip
python3 tool/ios_simulator_smoke.py
trap 'python3 tool/ios_simulator_smoke.py --cleanup' EXIT
SIM_ID="$(cat build/ios-preview/simulator-id.txt)"
flutter test integration_test/ios_remote_transfer_test.dart -d "$SIM_ID" \
  --dart-define=NAZZELHA_BACKEND=http://127.0.0.1:8127/api
python3 - <<'PY'
from pathlib import Path
import hashlib, json
root = Path('build/deliveries')
names = ['Nazzelha-iOS-Unsigned.ipa', 'Nazzelha-iOS-Simulator.zip']
(root / 'IOS-SHA256SUMS.txt').write_text(''.join(
    hashlib.sha256((root / name).read_bytes()).hexdigest() + '  ' + name + '\n'
    for name in names))
Path('build/ios-preview/integration-result.json').write_text(json.dumps({
    'passed': True, 'test': 'real iOS HTTP and Unicode disk transfer',
    'fixture_bytes_are_not_a_real_video': True}))
PY
