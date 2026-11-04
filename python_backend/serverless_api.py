"""Stateless Vercel API: stream each finished file into its visitor's browser.

No request depends on another function instance's memory or temporary disk.
The child process and its FFmpeg children are terminated on disconnect/timeout.
"""
import asyncio
import base64
import json
import os
import signal
import sys
import tempfile
import time
from contextlib import asynccontextmanager
import anyio
from pathlib import Path
from urllib.parse import urlparse

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, StreamingResponse

from media_core import valid_url
from public_api import safe_name

MAX_FILE_BYTES = 96 * 1024 * 1024
JOB_TIMEOUT = 225


def create_serverless_app(job_script=None, timeout=JOB_TIMEOUT):
    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
    job_script = Path(job_script or Path(__file__).with_name('main.py'))
    slots = asyncio.Semaphore(1)

    @app.middleware('http')
    async def boundary(request: Request, call_next):
        rewrite_route = request.query_params.get('_nazzelha_route')
        if rewrite_route in ('health', 'command', 'download', 'cancel'):
            request.scope['path'] = '/' + rewrite_route
        # Vercel may preserve the original request path or expose its rewrite.
        for prefix in ('/api/index.py', '/api'):
            if request.scope['path'].startswith(prefix + '/'):
                request.scope['path'] = request.scope['path'][len(prefix):]
                break
        origin = request.headers.get('origin')
        if origin:
            parsed = urlparse(origin)
            site = os.environ.get('NAZZELHA_SITE_ORIGIN', 'https://nazzelha.mohamed-fooda-mtf.workers.dev')
            same_host = parsed.hostname == request.url.hostname and parsed.scheme in ('http', 'https')
            if origin != site and not same_host:
                return JSONResponse(dict(error='Origin is not allowed.'), status_code=403)
        if request.method == 'POST':
            if request.headers.get('content-type', '').split(';')[0] != 'application/json':
                return JSONResponse(dict(error='JSON is required.'), status_code=415)
            body = bytearray()
            async for chunk in request.stream():
                body.extend(chunk)
                if len(body) > 32768:
                    return JSONResponse(dict(error='Request is too large.'), status_code=413)
            request._body = bytes(body)
        response = await call_next(request)
        response.headers['Cache-Control'] = 'private, no-store'
        response.headers['X-Content-Type-Options'] = 'nosniff'
        return response

    def validated(data, playlist=False):
        url, platform = data.get('url', ''), 'youtube' if playlist else data.get('platform', 'youtube')
        try:
            valid = isinstance(url, str) and len(url) <= 4096 and valid_url(url, platform) and urlparse(url).port in (None, 80, 443)
        except ValueError:
            valid = False
        if not valid:
            raise HTTPException(400, 'Please enter a valid link for the selected platform.')
        return url.strip(), platform

    async def terminate(process):
        if process.returncode is None:
            if os.name == 'posix':
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            else:
                process.kill()
        await process.wait()
        await process.stdout.read()

    @asynccontextmanager
    async def run_command(command, duration):
        environment = dict(os.environ, PYTHONUTF8='1', NAZZELHA_PUBLIC_SERVER='1',
                           NAZZELHA_MAX_FILE_BYTES=str(MAX_FILE_BYTES))
        environment['PYTHONPATH'] = os.pathsep.join(str(path) for path in sys.path if path)
        process = await asyncio.create_subprocess_exec(sys.executable, '-u', '-X', 'utf8', str(job_script),
            stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL, env=environment,
            start_new_session=os.name == 'posix', limit=1024 * 1024)
        try:
            process.stdin.write((json.dumps(command) + '\n').encode())
            await process.stdin.drain()
            process.stdin.close()
            deadline = time.monotonic() + duration
            async def messages():
                while True:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        raise TimeoutError()
                    line = await asyncio.wait_for(process.stdout.readline(), remaining)
                    if not line:
                        return
                    yield json.loads(line)
            yield messages()
        finally:
            with anyio.CancelScope(shield=True):
                await terminate(process)

    @app.get('/health')
    def health():
        return dict(ready=True, mode='public', transfer='browser', max_file_bytes=MAX_FILE_BYTES,
                    max_job_seconds=timeout)

    @app.post('/command')
    async def command(data: dict):
        action = data.get('action')
        if action == 'get_download_dir':
            return dict(success=True, download_dir='Browser downloads')
        if action not in ('get_playlist', 'get_qualities'):
            raise HTTPException(400, 'Unsupported command.')
        url, platform = validated(data, playlist=action == 'get_playlist')
        if slots.locked():
            raise HTTPException(429, 'The free service is busy. Please try again shortly.')
        async with slots:
            try:
                async with run_command(dict(action=action, url=url, platform=platform), min(timeout, 165)) as events:
                    async for result in events:
                        if 'success' in result:
                            return result
            except TimeoutError:
                return dict(success=False, error='Video extraction timed out. Please try again or use the app.')
        return dict(success=False, error='Could not prepare this video. Please try again.')

    @app.post('/download')
    async def download(data: dict):
        url, platform = validated(data)
        quality, mode = data.get('quality', 4320), data.get('mode', 'video')
        if type(quality) is not int or not 1 <= quality <= 8640 or mode not in ('audio', 'video'):
            raise HTTPException(400, 'Invalid download options.')
        if slots.locked():
            raise HTTPException(429, 'The free service is busy. Please try again shortly.')

        async def stream():
            async with slots:
                # TemporaryDirectory deletes only this invocation's directory.
                with tempfile.TemporaryDirectory(prefix='nazzelha-') as output:
                    try:
                        async with run_command(dict(action='download', url=url, platform=platform,
                                quality=quality, mode=mode, output_path=output), timeout) as events:
                            async for result in events:
                                if result.get('event') == 'progress':
                                    yield json.dumps({k: v for k, v in result.items() if k in
                                        ('event', 'percent', 'speed', 'eta', 'total_bytes', 'downloaded_bytes', 'phase')}) + '\n'
                                elif 'success' in result:
                                    if result.get('success') is not True:
                                        error = str(result.get('error', 'Download failed.'))
                                        if 'max-filesize' in error.lower() or 'max_filesize' in error.lower():
                                            error = 'The free web edition supports files up to 96 MB. Choose a lower quality or use the app.'
                                        yield json.dumps(dict(success=False, error=error)) + '\n'
                                        return
                                    path = Path(result.get('file', '')).resolve()
                                    if path.parent != Path(output).resolve() or not path.is_file():
                                        raise ValueError('Missing media')
                                    if path.stat().st_size > MAX_FILE_BYTES:
                                        yield json.dumps(dict(success=False, error='The free web edition supports files up to 96 MB. Choose a lower quality or use the app.')) + '\n'
                                        return
                                    filename = path.name
                                    if data.get('filename'):
                                        filename = Path(safe_name(data['filename'])).stem + path.suffix
                                    yield json.dumps(dict(event='file_start', filename=filename, size=path.stat().st_size)) + '\n'
                                    with path.open('rb') as file:
                                        while chunk := file.read(192 * 1024):
                                            yield json.dumps(dict(event='file_chunk', data=base64.b64encode(chunk).decode('ascii'))) + '\n'
                                            await asyncio.sleep(0)
                                    yield json.dumps(dict(success=True, transfer='browser', filename=filename)) + '\n'
                                    return
                        yield json.dumps(dict(success=False, error='Connection to the download service was lost.')) + '\n'
                    except TimeoutError:
                        yield json.dumps(dict(success=False, error='The free web edition allows about 4 minutes to prepare a video. Try a lower quality or use the app.')) + '\n'
                    except asyncio.CancelledError:
                        raise
                    except Exception:
                        yield json.dumps(dict(success=False, error='Could not prepare this video. Please try again.')) + '\n'

        return StreamingResponse(stream(), media_type='application/x-ndjson')

    @app.post('/cancel')
    def cancel():
        # The browser aborts its own streaming request. There is deliberately no
        # process-global cancellation endpoint which could affect another user.
        return dict(success=True)

    return app
