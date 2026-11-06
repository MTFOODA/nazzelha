"""Build the pinned QuickJS-NG CLI for Android 7+ and 16 KiB page devices.

Executables are packaged as libqjs.so so Android installs them in executable
nativeLibraryDir, just like the existing FFmpeg runtime. Never execute a binary
downloaded into the app's writable data directory.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
VERSION = '0.18.0'
COMMIT = 'd7215b0ad3fc2c562e8317fd9bca058fd4863804'
NDK_VERSION = '28.2.13676358'
ARCHITECTURES = {'armeabi-v7a': 40, 'arm64-v8a': 183, 'x86_64': 62}


def validate_elf(data, machine):
    if data[:4] != b'\x7fELF' or data[5] != 1:
        raise ValueError('Expected a little-endian Android ELF executable.')
    kind, actual_machine = struct.unpack_from('<HH', data, 16)
    if kind != 3 or actual_machine != machine:
        raise ValueError('Wrong ABI or executable is not PIE.')
    if data[4] == 2:
        phoff = struct.unpack_from('<Q', data, 32)[0]
        entry_size, count = struct.unpack_from('<HH', data, 54)
    elif data[4] == 1:
        phoff = struct.unpack_from('<I', data, 28)[0]
        entry_size, count = struct.unpack_from('<HH', data, 42)
    else:
        raise ValueError('Unsupported ELF class.')
    loads = []
    for i in range(count):
        offset = phoff + i * entry_size
        if struct.unpack_from('<I', data, offset)[0] != 1:
            continue
        if data[4] == 2:
            file_offset, address = struct.unpack_from('<QQ', data, offset + 8)
            alignment = struct.unpack_from('<Q', data, offset + 48)[0]
        else:
            file_offset, address = struct.unpack_from('<II', data, offset + 4)
            alignment = struct.unpack_from('<I', data, offset + 28)[0]
        if alignment < 16384 or file_offset % 16384 != address % 16384:
            raise ValueError('Executable does not support 16 KiB memory pages.')
        loads.append(alignment)
    if not loads:
        raise ValueError('Executable has no loadable segments.')
    return loads


def prepare():
    sdk = Path(os.environ.get('ANDROID_SDK_ROOT') or os.environ.get('ANDROID_HOME')
               or Path(os.environ['LOCALAPPDATA']) / 'Android/sdk')
    ndk = sdk / 'ndk' / NDK_VERSION
    cmake_bin = sdk / 'cmake/3.22.1/bin'
    cmake, ninja = cmake_bin / 'cmake.exe', cmake_bin / 'ninja.exe'
    toolchain = ndk / 'build/cmake/android.toolchain.cmake'
    strip = ndk / 'toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-strip.exe'
    if not all(p.is_file() for p in (cmake, ninja, toolchain, strip)):
        raise SystemExit('Install Android NDK ' + NDK_VERSION + ' and SDK CMake 3.22.1 first.')
    source = ROOT / '.cache' / ('quickjs-ng-' + COMMIT)
    source.parent.mkdir(parents=True, exist_ok=True)

    def run(*args, cwd=ROOT):
        subprocess.run([str(a) for a in args], cwd=cwd, check=True)

    if not source.exists():
        run('git', 'clone', '--depth', '1', '--branch', 'v' + VERSION,
            'https://github.com/quickjs-ng/quickjs.git', source)
    revision = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'],
                                       text=True).strip()
    if revision != COMMIT:
        raise SystemExit('QuickJS source differs from the verified upstream commit. Leaving it untouched.')
    if subprocess.check_output(['git', '-C', str(source), 'status', '--porcelain'], text=True).strip():
        raise SystemExit('QuickJS source has local edits. Leaving them untouched.')
    records = {}
    for abi, machine in ARCHITECTURES.items():
        output = ROOT / 'build/quickjs-android' / abi
        run(cmake, '-S', source, '-B', output, '-G', 'Ninja',
            '-DCMAKE_MAKE_PROGRAM=' + str(ninja),
            '-DCMAKE_TOOLCHAIN_FILE=' + str(toolchain), '-DANDROID_ABI=' + abi,
            '-DANDROID_PLATFORM=android-24', '-DCMAKE_BUILD_TYPE=Release',
            '-DBUILD_SHARED_LIBS=OFF', '-DQJS_ENABLE_INSTALL=OFF',
            '-DQJS_BUILD_EXAMPLES=OFF', '-DQJS_BUILD_WERROR=OFF',
            '-DCMAKE_EXE_LINKER_FLAGS=-Wl,-z,max-page-size=16384')
        run(cmake, '--build', output, '--target', 'qjs_exe', '--parallel', '4')
        binary = output / 'qjs'
        run(strip, '--strip-unneeded', binary)
        data = binary.read_bytes()
        alignments = validate_elf(data, machine)
        destination = ROOT / 'android/app/src/main/jniLibs' / abi / 'libqjs.so'
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(binary, destination)
        records[abi] = dict(bytes=len(data), sha256=hashlib.sha256(data).hexdigest(),
                            load_alignments=alignments)
    license_path = ROOT / 'android/app/src/main/assets/licenses/QUICKJS-NG.txt'
    license_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / 'LICENSE', license_path)
    report = dict(version=VERSION, upstream_commit=COMMIT, ndk=NDK_VERSION,
                  minimum_android_api=24, architectures=records)
    (ROOT / 'build/quickjs-android/manifest.json').write_text(
        json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('Prepared Android QuickJS-NG for all release ABIs.', flush=True)


if __name__ == '__main__':
    prepare()
