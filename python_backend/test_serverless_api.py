import json
import tempfile
import unittest
from pathlib import Path
from fastapi.testclient import TestClient
from serverless_api import create_serverless_app, public_result


FAKE_JOB = '''
import json, sys, time
from pathlib import Path
print(json.dumps(dict(ready=True)), flush=True)
command = json.loads(sys.stdin.readline())
if 'blocked' in command['url']:
    print(json.dumps(dict(success=False, error_code='AUTHENTICATION_REQUIRED',
        error='Authentication required', technical="Sign in to confirm you are not a bot.")), flush=True)
    sys.exit(0)
if 'slow' in command['url']:
    time.sleep(3)
if command['action'] == 'download':
    path = Path(command['output_path']) / 'عربي.mp4'
    path.write_bytes(b'a' * (5 * 1024 * 1024 + 7))
    print(json.dumps(dict(event='progress', percent=100)), flush=True)
    print(json.dumps(dict(success=True, file=str(path))), flush=True)
else:
    print(json.dumps(dict(success=True, qualities=[720,1080])), flush=True)
'''


class ServerlessTests(unittest.TestCase):
    def test_host_challenge_is_not_reported_as_publisher_restriction(self):
        raw = dict(success=False, error_code='AUTHENTICATION_REQUIRED',
                   error='Private or authentication required',
                   technical="Sign in to confirm you're not a bot.",
                   diagnostics={'private': 'internal trace'})
        result = public_result(raw, 'youtube')
        self.assertEqual(result['error_code'], 'HOSTING_RESTRICTED')
        self.assertNotIn('technical', result)
        self.assertNotIn('diagnostics', result)
        private = public_result(dict(raw, technical='This video is private.'), 'youtube')
        self.assertEqual(private['error_code'], 'AUTHENTICATION_REQUIRED')

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.job = Path(self.temp.name) / 'fake_job.py'
        self.job.write_text(FAKE_JOB, encoding='utf-8')
        self.client = TestClient(create_serverless_app(self.job))

    def tearDown(self):
        self.temp.cleanup()

    def test_paths_and_stateless_metadata(self):
        for prefix in ('', '/api', '/api/index.py'):
            self.assertEqual(self.client.get(prefix + '/health').json()['transfer'], 'browser')
        self.assertEqual(self.client.get('/api?_nazzelha_route=health').json()['ready'], True)
        self.assertEqual(self.client.post('/api/command', json=dict(action='get_qualities', url='https://youtube.com/watch?v=abcdefghijk')).json()['qualities'], [720, 1080])

    def test_host_challenge_is_preserved_in_metadata_and_stream_responses(self):
        request = dict(action='get_qualities', platform='youtube', url='https://youtube.com/blocked')
        result = self.client.post('/command', json=request).json()
        self.assertEqual(result['error_code'], 'HOSTING_RESTRICTED')
        response = self.client.post('/download', json=request)
        result = json.loads(response.text.strip())
        self.assertEqual(result['error_code'], 'HOSTING_RESTRICTED')
        self.assertNotIn('technical', result)

    def test_stream_over_payload_limit_and_no_temporary_host_paths(self):
        import base64
        response = self.client.post('/download', json=dict(url='https://youtube.com/watch?v=abcdefghijk', filename='اسم مختار'))
        self.assertEqual(response.status_code, 200)
        events = [json.loads(line) for line in response.text.splitlines()]
        start = next(e for e in events if e.get('event') == 'file_start')
        self.assertEqual(start['filename'], 'اسم مختار.mp4')
        chunks = [e['data'] for e in events if e.get('event') == 'file_chunk']
        self.assertGreater(len(chunks), 20)
        self.assertEqual(sum(len(base64.b64decode(chunk)) for chunk in chunks), start['size'])
        self.assertGreater(start['size'], 4.5 * 1024 * 1024)
        self.assertTrue(events[-1]['success'])
        self.assertEqual(events[-1]['transfer'], 'browser')
        self.assertNotIn('file', events[-1])
        self.assertNotIn(self.temp.name, response.text)

    def test_deadline_terminates_child_and_slot_can_be_reused(self):
        client = TestClient(create_serverless_app(self.job, timeout=.5))
        response = client.post('/download', json=dict(url='https://youtube.com/slow'))
        events = [json.loads(line) for line in response.text.splitlines()]
        self.assertFalse(events[-1]['success'])
        self.assertIn('minutes', events[-1]['error'])
        self.assertTrue(client.post('/command', json=dict(action='get_qualities', url='https://youtube.com/ok')).json()['success'])

    def test_private_commands_and_arbitrary_sources_are_rejected(self):
        self.assertEqual(self.client.post('/command', json=dict(action='configure_auth')).status_code, 400)
        for url in ('file:///etc/passwd', 'http://127.0.0.1', 'https://youtube.com.evil.test'):
            self.assertEqual(self.client.post('/download', json=dict(url=url)).status_code, 400)
        self.assertEqual(self.client.post('/download', json=dict(url='https://youtube.com'), headers={'Origin': 'https://evil.test'}).status_code, 403)
        self.assertEqual(self.client.get('/files/' + 'a' * 48).status_code, 404)


if __name__ == '__main__':
    unittest.main()
