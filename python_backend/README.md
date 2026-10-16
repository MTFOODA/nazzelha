# Python Backend - Nazzelha Video Downloader

The Python backend is a microservice that handles video extraction and downloading for the Nazzelha Flutter application.

## Architecture

The backend communicates with Flutter via stdin/stdout using JSON messages:

```
Flutter Desktop App
        ↓ JSON commands (stdin)
    Python Service
        ↓ yt-dlp
    Video Extraction & Download
        ↓ FFmpeg (merging)
    JSON responses (stdout) ↓
Flutter Desktop App
```

## Installation

### 1. Install Python dependencies

```bash
cd python_backend
pip install -r requirements.txt
```

### 2. Verify FFmpeg is installed

```bash
ffmpeg -version
```

If not installed, download from https://ffmpeg.org/download.html

## How It Works

### Service Entry Point

```bash
python main.py
```

When started, the service:
1. Initializes the backend
2. Sends `{"ready": true}` to stdout
3. Waits for JSON commands on stdin
4. Processes commands and sends responses to stdout
5. Continues until terminated

### Supported Commands

#### 1. `get_qualities`

Extract available video qualities from a URL.

**Request:**
```json
{
  "action": "get_qualities",
  "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
  "platform": "youtube"
}
```

**Success Response:**
```json
{
  "success": true,
  "qualities": [240, 360, 480, 720, 1080],
  "title": "Video Title"
}
```

**Error Response:**
```json
{
  "success": false,
  "error": "This video is unavailable or cannot be accessed."
}
```

#### 2. `download`

Download a video at the specified quality.

**Request:**
```json
{
  "action": "download",
  "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
  "platform": "youtube",
  "quality": 720,
  "output_path": "C:\\Users\\User\\Downloads\\Nazzelha"
}
```

**Success Response:**
```json
{
  "success": true,
  "file": "C:\\Users\\User\\Downloads\\Nazzelha\\Video Title.mp4",
  "title": "Video Title"
}
```

**Error Response:**
```json
{
  "success": false,
  "error": "FFmpeg is not installed. Please install FFmpeg from https://ffmpeg.org/download.html"
}
```

#### 3. `get_download_dir`

Get the default download directory.

**Request:**
```json
{
  "action": "get_download_dir"
}
```

**Response:**
```json
{
  "success": true,
  "download_dir": "C:\\Users\\User\\Downloads\\Nazzelha"
}
```

## Code Structure

### `main.py`

The main service entry point. Handles:
- Service initialization
- stdin/stdout communication
- JSON message parsing
- Command routing to appropriate handlers
- Error handling

Functions:
- `send_response(response)` - Send JSON response to stdout
- `handle_get_qualities(command)` - Extract available qualities
- `handle_download(command)` - Start video download
- `handle_get_download_dir(command)` - Get default download directory
- `process_command(line)` - Process a single JSON command
- `main()` - Service loop

### `downloader.py`

Core video download logic. Contains:
- `VideoDownloader` class with methods for extraction and downloading
- URL validation
- FFmpeg checking
- Progress tracking

Key Methods:
- `get_available_qualities(url, platform)` - Extract available video qualities
- `download_video(url, platform, quality, output_path)` - Download video
- `_check_ffmpeg()` - Verify FFmpeg installation
- `get_downloads_directory()` - Get default download directory
- `validate_url(url, platform)` - Validate URL format

## Quality Selection Logic

When downloading at a specific quality, yt-dlp format string used:

```
bestvideo[height<=<quality>]+bestaudio/best[height<=<quality>]
```

Example: For quality=720:
```
bestvideo[height<=720]+bestaudio/best[height<=720]
```

This:
1. Selects best video codec with height ≤ 720p
2. Selects best audio codec
3. Falls back to best overall format if separate video/audio unavailable
4. FFmpeg automatically merges to MP4

## Error Handling

The backend handles errors gracefully:

| Error | Cause | Message |
|-------|-------|---------|
| Invalid URL | Empty or malformed URL | "No video URL provided." |
| Wrong platform | URL doesn't match platform | "Invalid youtube URL..." |
| Video unavailable | Video deleted or private | "This video is unavailable..." |
| No qualities | No video tracks found | "No downloadable video qualities found" |
| FFmpeg missing | FFmpeg not installed/in PATH | "FFmpeg is not installed..." |
| Download failed | yt-dlp error | "Download failed: ..." |

Technical errors are wrapped in user-friendly messages. Full error details are logged internally.

## Platform Support

### YouTube
- Standard YouTube URLs: `https://www.youtube.com/watch?v=VIDEO_ID`
- Short URLs: `https://youtu.be/VIDEO_ID`
- Handles age-restricted content
- Respects video availability restrictions

### Facebook
- Facebook video URLs: `https://www.facebook.com/...`
- Facebook watch service: `https://fb.watch/...`
- Handles various Facebook video formats

## FFmpeg Integration

FFmpeg is automatically used for:
- Merging video and audio tracks
- Converting to MP4 format
- Audio re-encoding if necessary

If FFmpeg is missing, the service returns:
```json
{
  "success": false,
  "error": "FFmpeg is not installed. Please install FFmpeg..."
}
```

Install FFmpeg from: https://ffmpeg.org/download.html

## Logging

Debug information is logged to console. Verbose logging shows:
- Service initialization
- Command received
- Quality extraction progress
- Download progress
- Download completion

Enable with:
```python
from logger import Logger
logger = Logger()
logger.d('Debug message')
```

## Testing

### Test Quality Extraction

```bash
echo '{"action": "get_qualities", "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "platform": "youtube"}' | python main.py
```

### Test Download

```bash
echo '{"action": "download", "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "platform": "youtube", "quality": 720, "output_path": "C:\\Downloads\\Nazzelha"}' | python main.py
```

### Test Get Download Dir

```bash
echo '{"action": "get_download_dir"}' | python main.py
```

## Dependencies

- **yt-dlp**: Video extraction and downloading
  - GitHub: https://github.com/yt-dlp/yt-dlp
  - Handles YouTube, Facebook, and 1000+ other sites

- **FFmpeg**: Video/audio processing (external)
  - Website: https://ffmpeg.org
  - Must be installed separately and in system PATH

## Performance

- **Quality extraction**: ~2-5 seconds (depends on network)
- **Download speed**: Limited by internet connection and yt-dlp performance
- **Memory usage**: ~50-100MB during extraction, 100-300MB during download
- **CPU usage**: Minimal during download (mostly I/O bound)

## Troubleshooting

### "yt-dlp is not installed"
```bash
pip install yt-dlp
```

### "FFmpeg is not installed"
Download from https://ffmpeg.org/download.html and add to PATH

### "No module named 'yt_dlp'"
```bash
pip install -r requirements.txt
```

### Slow quality extraction
- Check internet connection
- Some videos take longer to extract
- Normal behavior for large playlists (handled by noplaylist setting)

### Download fails mid-way
- Check disk space
- Check internet connection stability
- Try with a lower quality setting

## Security Considerations

- Input validation: All URLs validated before processing
- Command injection: No shell commands, safe subprocess usage
- File system: Safe path handling with Path() objects
- Resource limits: FFmpeg and yt-dlp have timeout protection

## Future Enhancements

Potential improvements:
- Progress event streaming (real-time progress to Flutter)
- Batch downloads
- Download queue management
- Format customization (MP4, MKV, WebM, etc.)
- Subtitle extraction
- Playlist handling
- Custom output naming templates

## Development

### Adding a new command

1. Create handler function in `main.py`:
```python
def handle_new_command(command: Dict[str, Any]) -> Dict[str, Any]:
    """Handle NEW_COMMAND."""
    # Implementation
    return {"success": True, "data": result}
```

2. Register in `COMMAND_HANDLERS`:
```python
COMMAND_HANDLERS = {
    "get_qualities": handle_get_qualities,
    "download": handle_download,
    "new_command": handle_new_command,  # Add here
}
```

3. Test with stdin/stdout

### Modifying download logic

Edit `downloader.py` VideoDownloader class:
- Customize yt-dlp options in `download_video()`
- Add new quality formats
- Customize output naming in `outtmpl`

## References

- yt-dlp Documentation: https://github.com/yt-dlp/yt-dlp/wiki
- FFmpeg Documentation: https://ffmpeg.org/documentation.html
- Python subprocess: https://docs.python.org/3/library/subprocess.html
