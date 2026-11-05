"""Check a distributable APK independently of the Gradle build configuration."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import zipfile

CERTIFICATE = '18e10d4f4200ab4d54c82cf7c7e940ff9465488aee05240978d0610011c7d045'
ABIS = {'arm64-v8a', 'armeabi-v7a', 'x86_64'}


def check_elf(data, name, abi):
    if data[:4] != b'\x7fELF':
        raise ValueError('Invalid native library: ' + name)
    order = '<' if data[5] == 1 else '>'
    machine = struct.unpack_from(order + 'H', data, 18)[0]
    expected = {'arm64-v8a': (2, 183), 'armeabi-v7a': (1, 40), 'x86_64': (2, 62)}[abi]
    if (data[4], machine) != expected:
        raise ValueError('Native machine architecture does not match its ABI: ' + name)
    if abi == 'armeabi-v7a':
        return  # 16 KB page-size enforcement concerns 64-bit ABIs.
    offset = struct.unpack_from(order + 'Q', data, 32)[0]
    entry_size, count = struct.unpack_from(order + 'HH', data, 54)
    for i in range(count):
        pos = offset + i * entry_size
        if struct.unpack_from(order + 'I', data, pos)[0] == 1:
            if struct.unpack_from(order + 'Q', data, pos + 48)[0] < 16384:
                raise ValueError('Native library is not 16 KB aligned: ' + name)


def verify(apk, sdk):
    suffix = '.exe' if os.name == 'nt' else ''
    versions = [p for p in (sdk / 'build-tools').iterdir() if (p / ('aapt2' + suffix)).is_file()]
    tools = max(versions, key=lambda p: tuple(int(n) for n in re.findall(r'\d+', p.name)))
    signer = tools / ('apksigner.bat' if os.name == 'nt' else 'apksigner')
    result = subprocess.run([str(signer), 'verify', '--verbose', '--print-certs', str(apk)], check=True, capture_output=True, text=True)
    if not re.search(r'Verified using v[23](?:\.1)? scheme.*: true', result.stdout):
        raise ValueError('A modern APK signature scheme is required.')
    certificate = re.search(r'certificate SHA-256 digest: ([a-f0-9]+)', result.stdout)[1]
    if certificate != CERTIFICATE:
        raise ValueError('The APK is not signed with the existing release identity.')
    subprocess.run([str(tools / ('zipalign' + suffix)), '-c', '-P', '16', '4', str(apk)], check=True)
    metadata = subprocess.check_output([str(tools / ('aapt2' + suffix)), 'dump', 'badging', str(apk)], text=True, encoding='utf-8')
    package = re.search(r"package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", metadata)
    minimum = int(re.search(r"(?:minSdkVersion|sdkVersion):'(\d+)'", metadata)[1])
    if not package or package[1] != 'com.example.nazzelha' or minimum != 24:
        raise ValueError('Unexpected package identity or minimum Android version.')
    libraries = {}
    ffmpeg_libraries = {}
    with zipfile.ZipFile(apk) as archive:
        if archive.testzip() is not None:
            raise ValueError('The APK contains a corrupt ZIP member.')
        for abi in ABIS:
            names = [n for n in archive.namelist() if n.startswith('lib/' + abi + '/') and n.endswith('.so')]
            if not names:
                raise ValueError('Missing ABI: ' + abi)
            for required in ('libflutter.so', 'libapp.so', 'libffmpeg.so', 'libffprobe.so', 'libffmpeg.zip.so'):
                if 'lib/' + abi + '/' + required not in names:
                    raise ValueError('Missing ' + abi + '/' + required)
            libraries[abi] = len(names)
            for name in names:
                data = archive.read(name)
                if name.endswith('/libffmpeg.zip.so'):
                    if not data.startswith(b'PK'):
                        raise ValueError('Invalid FFmpeg library archive: ' + name)
                    with zipfile.ZipFile(io.BytesIO(data)) as packed:
                        if packed.testzip() is not None:
                            raise ValueError('Corrupt packed FFmpeg library: ' + name)
                        count = 0
                        for entry in packed.infolist():
                            payload = packed.read(entry)
                            if payload.startswith(b'\x7fELF'):
                                check_elf(payload, name + '/' + entry.filename, abi)
                                count += 1
                        if not count:
                            raise ValueError('Missing FFmpeg shared libraries: ' + name)
                        ffmpeg_libraries[abi] = count
                    continue
                check_elf(data, name, abi)
    return dict(package=package[1], version=package[3], version_code=int(package[2]), min_sdk=minimum,
                bytes=apk.stat().st_size, sha256=hashlib.file_digest(apk.open('rb'), 'sha256').hexdigest(),
                certificate_sha256=certificate, native_libraries=libraries,
                packed_ffmpeg_libraries=ffmpeg_libraries, zip_alignment_16k=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', nargs='?', default='build/deliveries/Nazzelha-Android.apk')
    parser.add_argument('--sdk', default=os.environ.get('ANDROID_SDK_ROOT') or os.environ.get('ANDROID_HOME') or str(Path(os.environ.get('LOCALAPPDATA', '')) / 'Android/sdk'))
    parser.add_argument('--expected-version')
    parser.add_argument('--expected-version-code', type=int)
    args = parser.parse_args()
    result = verify(Path(args.apk).resolve(), Path(args.sdk))
    if args.expected_version and result['version'] != args.expected_version:
        raise ValueError('The APK version does not match the release source.')
    if args.expected_version_code is not None and result['version_code'] != args.expected_version_code:
        raise ValueError('The APK version code does not match the release source.')
    print(json.dumps(result, indent=2))
