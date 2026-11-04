import io
import json
import tempfile
import threading
import unittest
import zipfile
from unittest.mock import patch
from pathlib import Path
from fastapi.testclient import TestClient
from public_api import create_app


class FakeEngine:
    def __init__(self, callback=None):
        self.callback = callback
        self._stop_download = False

    def get_available_qualities(self, *_):
        return dict(success=True, qualities=[720, 1080])

    def download_video(self, url, platform, quality, output, mode='video'):
        self.callback(dict(event='progress', percent=50, downloaded_bytes=3))
        path = Path(output) / 'فيديو.mp4'
        path.write_bytes(b'test-video')
        return dict(success=True, file=str(path))


class PublicAPITests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.app = create_app(self.directory.name, engine_factory=FakeEngine,
                              secret='test-only', secure_cookie=False)
        self.a = TestClient(self.app)
        self.b = TestClient(self.app)
        self.a.get('/health')
        self.b.get('/health')

    def tearDown(self):
        self.directory.cleanup()

    def prepare(self, client=None, **options):
        response = (client or self.a).post('/download', json={
            'url': 'https://youtube.com/watch?v=abcdefghijk', 'quality': 1080, **options})
        self.assertEqual(response.status_code, 200)
        return [json.loads(line) for line in response.text.splitlines()][-1]

    def test_private_files_range_and_unicode_attachment(self):
        result = self.prepare(filename='اسم عربي', folder_name='اناشيد عامة')
        link = result['file'].removeprefix('/api')
        response = self.a.get(link)
        self.assertEqual(response.content, b'test-video')
        self.assertIn("filename*=utf-8''", response.headers['content-disposition'])
        self.assertEqual(self.b.get(link).status_code, 404)
        self.assertEqual(self.a.get(link, headers={'Range': 'bytes=0-3'}).content, b'test')
        self.assertEqual(self.a.head(link).status_code, 200)
        self.assertEqual(self.a.get('/files/../../etc/passwd').status_code, 404)

    def test_playlist_zip_exact_arabic_folder_and_ownership(self):
        result = self.prepare()
        self.assertEqual(self.b.post('/archive', json={'folder': 'اناشيد عامة', 'files': [result['file']]}).status_code, 404)
        response = self.a.post('/archive', json={'folder': 'اناشيد عامة', 'files': [result['file']]})
        self.assertEqual(response.status_code, 200)
        archive = self.a.get(response.json()['file'].removeprefix('/api'))
        with zipfile.ZipFile(io.BytesIO(archive.content)) as value:
            self.assertEqual(value.namelist(), ['اناشيد عامة/فيديو.mp4'])

    def test_no_auth_import_filesystem_commands_or_arbitrary_urls(self):
        for action in ('configure_auth', 'get_auth_status', 'open_location', 'repair_playlist_folder'):
            self.assertEqual(self.a.post('/command', json={'action': action}).status_code, 400)
        for url in ('http://127.0.0.1/', 'file:///etc/passwd', 'https://youtube.com.evil.test/', 'https://youtube.com:1234/'):
            self.assertEqual(self.a.post('/download', json={'url': url}).status_code, 400)
        self.assertEqual(self.a.post('/command', json={'action': 'get_download_dir'}, headers={'Origin': 'https://evil.test'}).status_code, 403)
        self.assertEqual(TestClient(self.app).post('/download', json={'url': 'https://youtube.com/'}).status_code, 401)

    def test_retry_returns_existing_file_without_duplicate_work(self):
        first, second = self.prepare(), self.prepare()
        self.assertEqual(first['file'], second['file'])
        self.assertEqual(len(list(Path(self.directory.name).glob('*/*.mp4'))), 1)

    def test_expiration_removes_only_registered_files(self):
        result = self.prepare()
        link = result['file'].removeprefix('/api')
        unrelated = Path(self.directory.name) / 'unrelated.txt'
        unrelated.write_text('keep')
        with patch('public_api.time.time', return_value=result['expires_at'] + 1):
            self.assertEqual(self.a.get(link).status_code, 404)
            self.a.get('/health')
        self.assertFalse(list(Path(self.directory.name).glob('*/*.mp4')))
        self.assertTrue(unrelated.exists())

    def test_cancel_does_not_cancel_other_browser(self):
        entered, release = threading.Event(), threading.Event()
        engines = []

        class SlowEngine(FakeEngine):
            def download_video(self, *args, **kwargs):
                engines.append(self)
                entered.set()
                release.wait(5)
                if self._stop_download:
                    return dict(success=False, cancelled=True)
                return super().download_video(*args, **kwargs)

        app = create_app(self.directory.name, engine_factory=SlowEngine, secret='test-only', secure_cookie=False)
        a, b = TestClient(app), TestClient(app)
        a.get('/health')
        b.get('/health')
        result = []
        thread = threading.Thread(target=lambda: result.append(a.post('/download', json={'url': 'https://youtube.com/'})))
        thread.start()
        self.assertTrue(entered.wait(3))
        self.assertEqual(b.post('/cancel', json={}).status_code, 200)
        self.assertFalse(engines[0]._stop_download)
        a.post('/cancel', json={})
        self.assertTrue(engines[0]._stop_download)
        release.set()
        thread.join(6)
        self.assertTrue(json.loads(result[0].text.splitlines()[-1])['cancelled'])


if __name__ == '__main__':
    unittest.main()
