"""Loopback backend for Edge. Run: python python_backend/web_bridge.py."""
import json
import queue
import re
import threading
from pathlib import Path

import uvicorn
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, StreamingResponse

from downloader import VideoDownloader
from main import COMMAND_HANDLERS
from download_location import open_download_location

app = FastAPI()
app.add_middleware(CORSMiddleware,
                   allow_origin_regex=r'https?://(localhost|127\.0\.0\.1)(:\d+)?',
                   allow_methods=['GET', 'POST'], allow_headers=['Content-Type'])
engine_lock = threading.Lock()
active_downloader = None


@app.middleware('http')
async def check_local_origin(request: Request, call_next):
    origin = request.headers.get('origin')
    if origin and not re.fullmatch(r'https?://(localhost|127\.0\.0\.1)(:\d+)?', origin):
        return JSONResponse({'error': 'Only local app origins are allowed.'}, status_code=403)
    return await call_next(request)


@app.get('/health')
def health():
    return {'ready': True}


@app.post('/command')
def command(command: dict):
    action = command.get('action')
    if action not in COMMAND_HANDLERS or action == 'download':
        raise HTTPException(400, 'Unsupported command')
    if not engine_lock.acquire(blocking=False):
        return {'success': False, 'error': 'A download is already running. Please wait.'}
    try:
        return COMMAND_HANDLERS[action](command)
    except Exception as exc:
        return {'success': False, 'error': str(exc)}
    finally:
        engine_lock.release()


@app.post('/download')
def download(command: dict):
    global active_downloader
    if not engine_lock.acquire(blocking=False):
        raise HTTPException(409, 'A download is already running. Please wait.')
    events = queue.Queue()
    downloader = VideoDownloader(events.put)
    active_downloader = downloader

    def worker():
        global active_downloader
        try:
            platform = command.get('platform', 'youtube')
            folders = dict(youtube='YouTube', facebook='Facebook', instagram='Instagram', tiktok='TikTok')
            if platform not in folders:
                raise ValueError('Unsupported platform')
            root = Path(VideoDownloader.get_downloads_directory()).resolve()
            output = root / folders[platform]
            folder = command.get('folder_name')
            if folder:
                from yt_dlp.utils import sanitize_filename
                safe = sanitize_filename(folder, restricted=False).strip(' .')
                if not safe or safe in ('.', '..') or '/' in safe or '\\' in safe:
                    raise ValueError('Invalid folder name')
                output = output / 'Playlists' / safe
            result = downloader.download_video(
                command.get('url', ''), platform, int(command.get('quality', 4320)),
                str(output), mode=command.get('mode', 'video'))
            if result.get('success') and command.get('filename'):
                from yt_dlp.utils import sanitize_filename
                src = Path(result['file'])
                name = sanitize_filename(str(command['filename']), restricted=False)
                name = Path(name.replace('\\', '/')).name
                target = output / (Path(name).stem + src.suffix)
                counter = 1
                while target.exists() and target != src:
                    target = output / (Path(name).stem + f' ({counter})' + src.suffix)
                    counter += 1
                if src != target:
                    src.rename(target)
                result['file'] = str(target)
            events.put(result)
        except Exception as exc:
            events.put({'success': False, 'error': str(exc)})
        finally:
            active_downloader = None
            events.put(None)
            engine_lock.release()

    threading.Thread(target=worker, daemon=True).start()

    def stream():
        while True:
            event = events.get()
            if event is None:
                return
            yield json.dumps(event) + '\n'

    return StreamingResponse(stream(), media_type='application/x-ndjson')


@app.post('/open-location')
def open_location(command: dict):
    try:
        return open_download_location(command, VideoDownloader.get_downloads_directory())
    except Exception as exc:
        return {'success': False, 'error': str(exc)}


@app.post('/cancel')
def cancel():
    downloader = active_downloader
    if downloader is not None:
        downloader._stop_download = True
    return {'success': True}


if __name__ == '__main__':
    uvicorn.run(app, host='127.0.0.1', port=8000)
