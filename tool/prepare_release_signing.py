"""Create a persistent local release identity. Never writes secrets to stdout."""
import os
import secrets
import shutil
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parent.parent
private = root / '.release'
private.mkdir(exist_ok=True)
key = private / 'nazzelha-release.jks'
properties = private / 'signing.properties'
if key.exists() and properties.exists():
    print('The existing local Android release identity will be reused.')
elif key.exists() or properties.exists():
    raise SystemExit('Incomplete signing configuration; existing files were preserved.')
else:
    password = secrets.token_urlsafe(36)
    tool = shutil.which('keytool') or str(Path(os.environ.get('JAVA_HOME', r'C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot')) / 'bin/keytool.exe')
    env = dict(os.environ, NAZZELHA_SIGNING_PASSWORD=password)
    result = subprocess.run([tool, '-genkeypair', '-keystore', str(key), '-alias', 'nazzelha',
        '-keyalg', 'RSA', '-keysize', '3072', '-validity', '10000',
        '-dname', 'CN=Mohamed Fooda, OU=Nazzelha, O=Nazzelha, C=EG',
        '-storepass:env', 'NAZZELHA_SIGNING_PASSWORD', '-keypass:env', 'NAZZELHA_SIGNING_PASSWORD'],
        capture_output=True, env=env)
    if result.returncode:
        raise SystemExit('Release keystore generation failed; credentials were not printed.')
    properties.write_text(f'storeFile=../.release/nazzelha-release.jks\nstorePassword={password}\nkeyAlias=nazzelha\nkeyPassword={password}\n', encoding='utf-8')
    print('A new Android release identity was saved locally under .release (excluded from Git).')
