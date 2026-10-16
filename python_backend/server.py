"""
Simple FastAPI wrapper for the existing downloader logic so mobile (Android/iOS)
can call the Python backend over HTTP.

Endpoints provided:
- GET  /health                 -> {"ready": true}
- POST /command                -> accepts same JSON command as before and returns JSON response

This is intentionally simple and synchronous to get Android working quickly.
For production you'd likely implement background tasks and progress streaming (SSE/WebSocket).
"""
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Any, Dict
import uvicorn
import json

from downloader import VideoDownloader, validate_url

app = FastAPI()

class Command(BaseModel):
    action: str
    url: str = ""
    platform: str = "youtube"
    quality: int = 720
    output_path: str | None = None


@app.get("/health")
async def health() -> Dict[str, Any]:
    return {"ready": True}


@app.post("/command")
async def command_endpoint(cmd: Command):
    action = cmd.action.lower()

    try:
        if action == 'get_qualities':
            url = cmd.url.strip()
            platform = cmd.platform.lower()
            if not url:
                return {"success": False, "error": "No video URL provided."}
            if not validate_url(url, platform):
                return {"success": False, "error": f"Invalid {platform} URL."}
            downloader = VideoDownloader()
            return downloader.get_available_qualities(url, platform)

        elif action == 'download':
            url = cmd.url.strip()
            platform = cmd.platform.lower()
            quality = cmd.quality
            output_path = cmd.output_path or VideoDownloader.get_downloads_directory()

            if not url:
                return {"success": False, "error": "No video URL provided."}

            # ensure output dir
            try:
                from pathlib import Path
                Path(output_path).mkdir(parents=True, exist_ok=True)
            except Exception as e:
                return {"success": False, "error": f"Cannot create output directory: {e}"}

            downloader = VideoDownloader()
            # Run download synchronously and return terminal response
            try:
                return downloader.download_video(url, platform, quality, output_path)
            except Exception as e:
                return {"success": False, "error": str(e)}

        elif action == 'get_download_dir':
            return {"success": True, "download_dir": VideoDownloader.get_downloads_directory()}

        else:
            return {"success": False, "error": f"Unknown action: {action}"}

    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


if __name__ == '__main__':
    uvicorn.run(app, host='0.0.0.0', port=8000)
