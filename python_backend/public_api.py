"""Multi-user web API. Never publish the development-only web_bridge.py."""
import hashlib
import hmac
import json
import os
import queue
import re
import secrets
import shutil
import threading
import time
import zipfile
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlparse

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse

from downloader import VideoDownloader
from media_core import extract_playlist, valid_url


@dataclass
class SavedFile:
    owner: str
    path: Path
    expires: float
    folder: str = ''


def safe_name(value, fallback='Playlist'):
    from yt_dlp.utils import sanitize_filename
    value = sanitize_filename(str(value or ''), restricted=False)
    value = re.sub(r'[\\/\x00-\x1f]', '_', value).strip(' .')[:150]
    return value if value and value not in ('.', '..') else fallback


def create_app(root=None, engine_factory=VideoDownloader, playlist_extractor=extract_playlist,
               secret=None, secure_cookie=True, ttl=3600, max_file_bytes=256 * 1024 * 1024):
    root = Path(root or os.environ.get('NAZZELHA_STORAGE', '/tmp/nazzelha')).resolve()
    root.mkdir(parents=True, exist_ok=True)
    secret = (secret or os.environ.get('NAZZELHA_SESSION_SECRET') or secrets.token_hex(32)).encode()
    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
    files = {}
    completed = {}
    active = {}
    state_lock = threading.RLock()
    engine_slot = threading.Semaphore(1)
    waiting_slots = threading.BoundedSemaphore(8)
    origin = os.environ.get('NAZZELHA_SITE_ORIGIN', 'https://nazzelha.mohamed-fooda-mtf.workers.dev').rstrip('/')
    max_cache_bytes = int(os.environ.get('NAZZELHA_MAX_CACHE_BYTES', 1024 * 1024 * 1024))
    file_pattern = re.compile(r'^(?:/api)?/files/([a-f0-9]{48})$')

    def signature(value):
        return hmac.new(secret, value.encode(), hashlib.sha256).hexdigest()

    def owner(request):
        cookie = request.cookies.get('nazzelha_session', '')
        value, _, digest = cookie.partition('.')
        if not re.fullmatch(r'[a-f0-9]{48}', value) or not hmac.compare_digest(signature(value), digest):
            raise HTTPException(401, 'Please reconnect to the download service.')
        return value

    def cleanup():
        # Only delete directories that this process created and registered.
        with state_lock:
            for token, saved in list(files.items()):
                if saved.expires < time.time():
                    files.pop(token)
                    if saved.path.parent.parent == root:
                        shutil.rmtree(saved.path.parent, ignore_errors=True)
            for key, token in list(completed.items()):
                if token not in files:
                    completed.pop(key)

    def save_file(user, path, folder=''):
        path = path.resolve()
        if path.parent.parent != root or not path.is_file():
            raise ValueError('The download did not produce a file.')
        if path.stat().st_size > max_file_bytes and path.suffix != '.zip':
            raise ValueError('The free web edition supports files up to 256 MB. Choose a lower quality or use the app.')
        token = secrets.token_hex(24)
        with state_lock:
            files[token] = SavedFile(user, path, time.time() + ttl, folder)
        return token

    def lookup(user, token):
        with state_lock:
            saved = files.get(token)
            if not saved or saved.owner != user or saved.expires < time.time() or not saved.path.is_file():
                raise HTTPException(404, 'This temporary file expired. Prepare the video again.')
            return saved

    def result_for(user, token):
        saved = lookup(user, token)
        return dict(success=True, file='/api/files/' + token, filename=saved.path.name,
                    expires_at=saved.expires, size=saved.path.stat().st_size)

    def validated(data):
        platform = data.get('platform', 'youtube')
        url = data.get('url', '')
        if not isinstance(url, str) or len(url) > 4096 or not valid_url(url, platform):
            raise HTTPException(400, 'Please enter a valid link for the selected platform.')
        parsed = urlparse(url)
        if parsed.port not in (None, 80, 443):
            raise HTTPException(400, 'Invalid video URL.')
        return url.strip(), platform

    @app.middleware('http')
    async def boundary(request, call_next):
        supplied_origin = request.headers.get('origin')
        if supplied_origin and supplied_origin != origin:
            return JSONResponse({'error': 'Origin is not allowed.'}, status_code=403)
        if request.method == 'POST':
            if request.headers.get('content-type', '').split(';')[0] != 'application/json':
                return JSONResponse({'error': 'JSON is required.'}, status_code=415)
            try:
                body = bytearray()
                async for chunk in request.stream():
                    body.extend(chunk)
                    if len(body) > 32768:
                        return JSONResponse({'error': 'Request is too large.'}, status_code=413)
                request._body = bytes(body)
            except Exception:
                return JSONResponse({'error': 'Invalid request.'}, status_code=400)
        response = await call_next(request)
        response.headers['Cache-Control'] = 'private, no-store'
        response.headers['X-Content-Type-Options'] = 'nosniff'
        return response

    @app.get('/health')
    def health(request: Request):
        cleanup()
        try:
            user = owner(request)
        except HTTPException:
            user = secrets.token_hex(24)
        response = JSONResponse(dict(ready=True, mode='public', api_version=1,
                                     max_file_bytes=max_file_bytes, file_ttl_seconds=ttl))
        response.set_cookie('nazzelha_session', user + '.' + signature(user),
                            max_age=7 * 86400, httponly=True, secure=secure_cookie,
                            samesite='lax', path='/')
        return response

    @app.post('/command')
    def command(request: Request, data: dict):
        owner(request)
        action = data.get('action')
        if action == 'get_download_dir':
            return dict(success=True, download_dir='Browser downloads')
        if action not in ('get_qualities', 'get_playlist'):
            raise HTTPException(400, 'Unsupported command.')
        url, platform = validated({**data, 'platform': 'youtube'} if action == 'get_playlist' else data)
        if not engine_slot.acquire(blocking=False):
            raise HTTPException(429, 'The free service is busy. Please try again shortly.')
        try:
            if action == 'get_playlist':
                return playlist_extractor(url)
            return engine_factory().get_available_qualities(url, platform)
        except Exception:
            return dict(success=False, error='This video is restricted by its publisher.')
        finally:
            engine_slot.release()

    @app.post('/download')
    def download(request: Request, data: dict):
        user = owner(request)
        url, platform = validated(data)
        quality = data.get('quality', 4320)
        mode = data.get('mode', 'video')
        if type(quality) is not int or not 1 <= quality <= 8640 or mode not in ('audio', 'video'):
            raise HTTPException(400, 'Invalid download options.')
        cleanup()
        folder = safe_name(data.get('folder_name')) if data.get('folder_name') else ''
        filename = safe_name(data.get('filename'), '')
        key = (user, hashlib.sha256(json.dumps([url, platform, quality, mode, folder, filename]).encode()).hexdigest())
        with state_lock:
            if key in completed:
                return StreamingResponse(iter([json.dumps(result_for(user, completed[key])) + '\n']),
                                         media_type='application/x-ndjson')
            if user in active:
                raise HTTPException(409, 'A download is already running in this browser.')
            if not waiting_slots.acquire(blocking=False):
                raise HTTPException(429, 'The free service is busy. Please try again shortly.')
            size = sum(f.path.stat().st_size for f in files.values() if f.path.is_file())
            if size >= max_cache_bytes:
                waiting_slots.release()
                raise HTTPException(429, 'Temporary storage is full. Please try later or use the app.')
            events = queue.Queue(maxsize=100)
            stop = threading.Event()
            job = dict(stop=stop, engine=None)
            active[user] = job

        def emit(event):
            if event.get('event') == 'progress':
                if event.get('downloaded_bytes', 0) > max_file_bytes:
                    raise ValueError('The free web edition supports files up to 256 MB. Use the app for larger files.')
                if events.qsize() < 95:
                    events.put_nowait(event)

        def worker():
            directory = root / secrets.token_hex(24)
            token = None
            try:
                with engine_slot:
                    if stop.is_set():
                        raise InterruptedError()
                    directory.mkdir()
                    engine = engine_factory(emit)
                    job['engine'] = engine
                    timer = threading.Timer(1200, lambda: setattr(engine, '_stop_download', True))
                    timer.daemon = True
                    timer.start()
                    try:
                        result = engine.download_video(url, platform, quality, str(directory), mode=mode)
                    finally:
                        timer.cancel()
                    if stop.is_set() or result.get('cancelled'):
                        raise InterruptedError()
                    if not result.get('success'):
                        events.put(dict(success=False, error=result.get('error', 'Download failed.')))
                        return
                    path = Path(result['file']).resolve()
                    if path.parent != directory or not path.is_file():
                        raise ValueError('The download did not produce a file.')
                    if filename:
                        renamed = directory / (Path(filename).stem + path.suffix)
                        path.rename(renamed)
                        path = renamed
                    token = save_file(user, path, folder)
                    with state_lock:
                        completed[key] = token
                    events.put(result_for(user, token))
            except InterruptedError:
                events.put(dict(success=False, cancelled=True, error='Download cancelled.'))
            except Exception as exc:
                message = str(exc)
                events.put(dict(success=False, error=message if '256 MB' in message else 'Could not prepare this video. Please try again.'))
            finally:
                if token is None:
                    shutil.rmtree(directory, ignore_errors=True)
                with state_lock:
                    active.pop(user, None)
                waiting_slots.release()
                events.put(None)

        threading.Thread(target=worker, daemon=True).start()

        def stream():
            while True:
                try:
                    event = events.get(timeout=15)
                except queue.Empty:
                    yield json.dumps(dict(event='progress', percent=0, speed='Waiting', eta='--:--')) + '\n'
                    continue
                if event is None:
                    return
                yield json.dumps(event) + '\n'

        return StreamingResponse(stream(), media_type='application/x-ndjson')

    @app.post('/cancel')
    def cancel(request: Request):
        user = owner(request)
        with state_lock:
            job = active.get(user)
            if job:
                job['stop'].set()
                if job['engine'] is not None:
                    job['engine']._stop_download = True
        return dict(success=True)

    @app.api_route('/files/{token}', methods=['GET', 'HEAD'])
    def get_file(request: Request, token: str):
        saved = lookup(owner(request), token)
        return FileResponse(saved.path, filename=saved.path.name,
                            media_type='application/octet-stream')

    @app.post('/archive')
    def archive(request: Request, data: dict):
        user = owner(request)
        requested = data.get('files')
        if not isinstance(requested, list) or not 1 <= len(requested) <= 200:
            raise HTTPException(400, 'Choose between 1 and 200 prepared videos per ZIP.')
        selected = []
        for item in dict.fromkeys(requested):
            match = file_pattern.fullmatch(str(item))
            if not match:
                raise HTTPException(400, 'Invalid file reference.')
            saved = lookup(user, match.group(1))
            if saved.path.suffix == '.zip':
                raise HTTPException(400, 'Choose video files.')
            selected.append(saved)
        archive_size = sum(f.path.stat().st_size for f in selected)
        if archive_size > max_cache_bytes:
            raise HTTPException(413, 'Please save these videos individually.')
        folder = safe_name(data.get('folder'))
        if not engine_slot.acquire(blocking=False):
            raise HTTPException(429, 'The free service is busy. Please try again shortly.')
        directory = root / secrets.token_hex(24)
        try:
            cleanup()
            with state_lock:
                used = sum(f.path.stat().st_size for f in files.values() if f.path.is_file())
            if used + archive_size > max_cache_bytes:
                raise HTTPException(429, 'Temporary storage is full. Please save videos individually or use the app.')
            directory.mkdir()
            path = directory / (folder + '.zip')
            with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_STORED) as archive_file:
                names = set()
                for i, saved in enumerate(selected, 1):
                    name = saved.path.name
                    if name in names:
                        name = f'{i:03d} - {name}'
                    names.add(name)
                    archive_file.write(saved.path, folder + '/' + name)
            token = save_file(user, path, folder)
            return result_for(user, token)
        except Exception:
            shutil.rmtree(directory, ignore_errors=True)
            raise
        finally:
            engine_slot.release()

    return app


if __name__ == '__main__':
    import uvicorn
    os.environ['NAZZELHA_PUBLIC_SERVER'] = '1'
    os.environ.setdefault('NAZZELHA_MAX_FILE_BYTES', str(256 * 1024 * 1024))
    uvicorn.run(create_app(), host='0.0.0.0', port=int(os.environ.get('PORT', 8000)),
                proxy_headers=True, forwarded_allow_ips='*')
