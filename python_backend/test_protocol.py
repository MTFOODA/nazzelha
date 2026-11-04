import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class ProtocolTests(unittest.TestCase):
    def test_windows_ansi_environment_does_not_corrupt_arabic_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / 'اناشيد عامة — اختبار 🎵'
            script = (
                "import main; from pathlib import Path; "
                "main.COMMAND_HANDLERS['protocol_probe'] = lambda c: "
                "(Path(c['path']).mkdir(parents=True, exist_ok=True) or "
                "{'success': True, 'path': c['path']}); main.main()"
            )
            env = dict(os.environ, PYTHONIOENCODING='cp1252', PYTHONUTF8='0')
            result = subprocess.run([sys.executable, '-c', script],
                cwd=Path(__file__).parent,
                input=(json.dumps({'action': 'protocol_probe', 'path': str(folder)}, ensure_ascii=False) + '\n').encode('utf-8'),
                capture_output=True, env=env, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr.decode('utf-8', errors='replace'))
            response = json.loads(result.stdout.decode('utf-8').splitlines()[-1])
            self.assertEqual(response['path'], str(folder))
            self.assertTrue(folder.is_dir())
            self.assertEqual(len(list(Path(tmp).iterdir())), 1)


if __name__ == '__main__':
    unittest.main()
