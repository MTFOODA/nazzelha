"""Offline Android runtime wiring checks; real device acceptance is separate."""
import importlib.util
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'android/app/src/main/python'))
from android_javascript import AndroidJavaScriptRuntime
import android_backend

spec = importlib.util.spec_from_file_location('prepare_android_javascript', ROOT / 'tool/prepare_android_javascript.py')
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)


class AndroidJavaScriptTests(unittest.TestCase):
    def test_private_diagnostics_remove_signed_queries_and_credentials(self):
        logger = android_backend._CaptureLogger(capacity=2)
        logger.debug('Loading https://media.example/file?sig=private-signed-value&expires=123')
        logger.debug('Authorization: private-account-value')
        tail = '\n'.join(logger.tail())
        self.assertNotIn('private-signed-value', tail)
        self.assertNotIn('private-account-value', tail)
        self.assertIn('https://media.example/file?<redacted>', tail)

    def test_packaged_runtime_is_enabled_for_both_youtube_modes_only(self):
        with tempfile.TemporaryDirectory() as folder:
            binary = Path(folder) / 'libqjs.so'
            binary.write_bytes(b'fixture, not an executable')
            runtime = AndroidJavaScriptRuntime()
            response = subprocess.CompletedProcess([], 0, '{"answer":42}\n', '')
            with patch('android_javascript.importlib.util.find_spec', return_value=object()), \
                    patch('android_javascript.os.access', return_value=True), \
                    patch('android_javascript.subprocess.run', return_value=response):
                runtime.configure(folder)
            self.assertTrue(runtime.available)
            with patch.object(android_backend, '_JAVASCRIPT_RUNTIME', runtime):
                for mode in ('audio', 'video'):
                    opts = android_backend._get_yt_dlp_opts('youtube', 4320, Path(folder), mode)
                    self.assertEqual(opts['js_runtimes'], {'quickjs': {'path': str(binary)}})
                self.assertNotIn('js_runtimes', android_backend._get_yt_dlp_opts('facebook', 720, Path(folder)))

    def test_solver_or_executable_failure_does_not_become_a_publisher_error(self):
        for solver in (None, object()):
            runtime = AndroidJavaScriptRuntime()
            with patch('android_javascript.importlib.util.find_spec', return_value=solver):
                runtime.configure('')
            self.assertFalse(runtime.available)
            self.assertEqual(runtime.options(), {})
            self.assertEqual(runtime.failure()['error_code'], 'LOCAL_RUNTIME_MISSING')
        with patch.object(android_backend, '_JAVASCRIPT_RUNTIME', runtime):
            import json
            for result in (
                android_backend.get_qualities('https://youtube.com/watch?v=abcdefghijk', 'youtube'),
                android_backend.download_video('https://youtube.com/watch?v=abcdefghijk', 'youtube', 720, ''),
            ):
                self.assertEqual(json.loads(result)['error_code'], 'LOCAL_RUNTIME_MISSING')

    def test_runtime_that_cannot_execute_is_not_advertised_as_ready(self):
        with tempfile.TemporaryDirectory() as folder:
            (Path(folder) / 'libqjs.so').write_bytes(b'fixture')
            runtime = AndroidJavaScriptRuntime()
            with patch('android_javascript.importlib.util.find_spec', return_value=object()), \
                    patch('android_javascript.os.access', return_value=True), \
                    patch('android_javascript.subprocess.run', side_effect=OSError('exec failed')):
                diagnostics = runtime.configure(folder)
            self.assertFalse(diagnostics['available'])
            self.assertIn('exec failed', diagnostics['error'])

    def test_packager_rejects_wrong_abi_and_four_kib_only_load_segments(self):
        data = bytearray(128)
        data[:6] = b'\x7fELF\x02\x01'
        struct.pack_into('<HH', data, 16, 3, 183)
        struct.pack_into('<Q', data, 32, 64)
        struct.pack_into('<HH', data, 54, 56, 1)
        struct.pack_into('<I', data, 64, 1)
        struct.pack_into('<Q', data, 112, 16384)
        self.assertEqual(packager.validate_elf(data, 183), [16384])
        with self.assertRaises(ValueError):
            packager.validate_elf(data, 40)
        struct.pack_into('<Q', data, 112, 4096)
        with self.assertRaises(ValueError):
            packager.validate_elf(data, 183)


if __name__ == '__main__':
    unittest.main()
