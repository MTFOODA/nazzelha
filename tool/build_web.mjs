import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync } from 'node:fs';
import path from 'node:path';

if (process.env.NAZZELHA_SKIP_WEB_BUILD === '1') {
  if (!existsSync('build/web/main.dart.js')) throw new Error('Build web before skipping the build hook.');
  process.exit(0);
}
const version = '3.47.7';
let flutter = process.env.FLUTTER_BIN;
if (!flutter) {
  const cached = path.resolve('.cache/flutter');
  if (!existsSync(path.join(cached, 'bin/flutter'))) {
    mkdirSync('.cache', { recursive: true });
    execFileSync('git', ['clone', '--depth', '1', '--branch', version,
      'https://github.com/flutter/flutter.git', cached], { stdio: 'inherit' });
  }
  flutter = path.join(cached, 'bin/flutter');
}
const run = args => execFileSync(flutter, args, { stdio: 'inherit', shell: process.platform === 'win32',
  env: { ...process.env, CI: 'true', FLUTTER_SUPPRESS_ANALYTICS: 'true' } });
run(['config', '--no-analytics']);
run(['pub', 'get', '--no-example']);
run(['build', 'web', '--release', '--no-web-resources-cdn',
  '--dart-define=NAZZELHA_BACKEND=/api', '--dart-define=NAZZELHA_PUBLIC_WEB=true']);
