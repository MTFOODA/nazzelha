"""Extraction rules shared by desktop, the local web bridge and Android."""
import re
import os
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import yt_dlp

HOSTS = {
    'youtube': ('youtube.com', 'youtu.be'),
    'facebook': ('facebook.com', 'fb.watch'),
    'instagram': ('instagram.com', 'instagr.am'),
    'tiktok': ('tiktok.com',),
}
_cookie_directory = None


def video_qualities(info):
    """Return media resolutions, excluding audio and storyboard images."""
    formats = [f for f in info.get('formats', [])
               if f.get('vcodec') != 'none' and f.get('protocol') != 'mhtml'
               and f.get('ext') not in ('mhtml', 'jpg', 'jpeg', 'png', 'webp')]
    heights = {int(f['height']) for f in formats
               if isinstance(f.get('height'), (int, float)) and f['height'] > 0}
    if heights:
        return sorted(heights)
    return [4320] if any(f.get('url') for f in formats) else []


def configure_cookie_directory(directory):
    global _cookie_directory
    _cookie_directory = Path(directory)


def cookie_path(platform):
    if platform not in HOSTS:
        raise ValueError('Unsupported platform')
    root = _cookie_directory or Path(os.environ.get('APPDATA') or Path.home() / '.config') / 'Nazzelha' / 'sessions'
    return root / (platform + '.txt')


def configure_auth(command):
    platform = command.get('platform', 'facebook')
    path = cookie_path(platform)
    content = command.get('content')
    if content is None:
        path.unlink(missing_ok=True)
    else:
        if not isinstance(content, str) or len(content.encode('utf-8')) > 1024 * 1024:
            raise ValueError('The session file must be a cookies.txt file smaller than 1 MB.')
        lines = ['# Netscape HTTP Cookie File']
        for line in content.lstrip('\ufeff').splitlines():
            if not line.strip() or (line.startswith('#') and not line.startswith('#HttpOnly_')):
                continue
            fields = line.split('\t')
            if len(fields) != 7:
                raise ValueError('Please choose a Netscape-format cookies.txt file.')
            domain = fields[0].removeprefix('#HttpOnly_').lstrip('.').lower()
            if not any(domain == host or domain.endswith('.' + host) for host in HOSTS[platform]):
                continue
            if fields[1] not in ('TRUE', 'FALSE') or fields[3] not in ('TRUE', 'FALSE'):
                raise ValueError('Invalid cookies.txt format.')
            if not fields[4].isdigit() or not fields[2].startswith('/'):
                raise ValueError('Invalid cookies.txt format.')
            lines.append(line)
        if len(lines) == 1:
            raise ValueError('This file contains no session cookies for the selected platform.')
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix('.tmp')
        temporary.write_text('\n'.join(lines) + '\n', encoding='utf-8')
        if os.name != 'nt':
            temporary.chmod(0o600)
        temporary.replace(path)
    return auth_status()


def auth_status():
    return dict(success=True, platforms={platform: cookie_path(platform).is_file() for platform in HOSTS})


def repair_playlist_folder(root, folder, files):
    """Recover only the known UTF-8/Windows-code-page alias of this folder."""
    root = Path(root).resolve()
    if not folder or folder in ('.', '..') or any(c in folder for c in '/\\:'):
        raise ValueError('Invalid playlist folder name')
    target_dir = (root / folder).resolve()
    if target_dir.parent != root:
        raise ValueError('Invalid playlist folder path')
    aliases = set()
    for encoding in ('cp1252', 'latin1'):
        try:
            alias = folder.encode('utf-8').decode(encoding)
            if alias != folder:
                aliases.add((root / alias).resolve())
        except UnicodeError:
            pass
    moved = {}
    for raw in files:
        src = Path(raw).resolve()
        if src.parent not in aliases or src.parent.parent != root or not src.is_file():
            continue
        target_dir.mkdir(parents=True, exist_ok=True)
        target = target_dir / src.name
        counter = 1
        while target.exists():
            target = target_dir / f'{src.stem} ({counter}){src.suffix}'
            counter += 1
        src.rename(target)
        moved[raw] = str(target)
    for directory in aliases:
        if directory.parent == root and directory.is_dir():
            try:
                directory.rmdir()  # Only empty, known aliases are removed.
            except OSError:
                pass
    return dict(success=True, files=moved, folder=str(target_dir))
USER_AGENT = ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/131.0.0.0 Safari/537.36')


class PublicMediaUnavailable(yt_dlp.utils.DownloadError):
    pass


def valid_url(url, platform=None):
    try:
        parsed = urlparse(url.strip())
        host = (parsed.hostname or '').lower()
        if parsed.scheme not in ('http', 'https') or not host or parsed.username or parsed.password:
            return False
        domains = HOSTS.get(platform, ()) if platform else sum(HOSTS.values(), ())
        return any(host == d or host.endswith('.' + d) for d in domains)
    except ValueError:
        return False


def playlist_url(url):
    if not valid_url(url, 'youtube'):
        raise ValueError('Please enter a YouTube playlist URL containing list=.')
    playlist_id = parse_qs(urlparse(url).query).get('list', [''])[0]
    if not re.fullmatch(r'[A-Za-z0-9_-]+', playlist_id):
        raise ValueError('Please enter a YouTube playlist URL containing list=.')
    return 'https://www.youtube.com/playlist?list=' + playlist_id


def extraction_options(platform):
    opts = dict(quiet=True, no_warnings=True, noplaylist=True,
                socket_timeout=25, retries=3, fragment_retries=3,
                extractor_retries=2, windowsfilenames=True,
                skip_unavailable_fragments=False)
    if platform == 'youtube':
        # Prefer direct HTTPS at the same resolution/fps. Premium HLS streams
        # may be advertised but refuse every fragment without a session/token.
        opts.update(format_sort=['res', 'fps', 'proto:https'], format_sort_force=True)
    if platform in HOSTS and cookie_path(platform).is_file():
        opts['cookiefile'] = str(cookie_path(platform))
    if platform in ('facebook', 'instagram'):
        opts['http_headers'] = {
            'User-Agent': USER_AGENT,
            'Referer': 'https://www.' + platform + '.com/',
        }
    return opts


def extract_media(ydl, url, platform, download=False):
    if not valid_url(url, platform):
        raise ValueError('Invalid ' + platform + ' URL.')
    try:
        info = ydl.extract_info(url.strip(), download=download)
    except yt_dlp.utils.DownloadError as exc:
        # Share links can resolve to a page layout the extractor cannot parse.
        # Retry the same public video using its canonical watch URL, only for
        # extraction errors. Never retry a media transfer or an auth failure.
        match = re.search(r'\[facebook\]\s+(\d+):\s+(?:Cannot parse data|Unable to extract)', str(exc))
        if platform != 'facebook' or not match:
            raise
        canonical = 'https://www.facebook.com/watch/?v=' + match.group(1)
        try:
            if canonical == url:
                raise exc
            info = ydl.extract_info(canonical, download=download)
        except yt_dlp.utils.DownloadError as canonical_error:
            if 'Cannot parse data' not in str(canonical_error):
                raise
            raise PublicMediaUnavailable(
                'Facebook did not return downloadable video data for this link. '
                'Open it in Facebook and check that the video is still available '
                'and plays without signing in. It may require a logged-in session '
                'or be temporarily unavailable to the downloader.') from canonical_error
    if info and info.get('_type') in ('playlist', 'multi_video'):
        info = next((item for item in info.get('entries', []) if item), None)
    if not info:
        raise ValueError('The platform returned no downloadable media.')
    return info


def extract_playlist(url):
    url = playlist_url(url)
    opts = extraction_options('youtube')
    opts.update(noplaylist=False, extract_flat='in_playlist', ignoreerrors=False,
                skip_download=True)
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(url, download=False)
    if not info:
        raise ValueError('The playlist is unavailable or private.')
    entries = []
    unavailable = 0
    for index, entry in enumerate(info.get('entries') or [], 1):
        if not entry or not entry.get('id'):
            unavailable += 1
            continue
        video_id = entry['id']
        if not re.fullmatch(r'[A-Za-z0-9_-]{11}', video_id):
            unavailable += 1
            continue
        availability = entry.get('availability')
        entries.append(dict(id=video_id, url='https://www.youtube.com/watch?v=' + video_id,
                            title=entry.get('title') or video_id, index=index,
                            unavailable=availability in ('private', 'premium_only', 'subscriber_only'),
                            duration=entry.get('duration')))
    if not entries:
        raise ValueError('No videos were found in this playlist.')
    return dict(success=True, id=info.get('id'), title=info.get('title') or 'YouTube playlist',
                entries=entries, unavailable=unavailable)


def final_filepath(ydl, info, mode='video'):
    candidates = [info.get('filepath')]
    candidates += [rd.get('filepath') for rd in info.get('requested_downloads') or []]
    base = ydl.prepare_filename(info)
    if mode == 'audio':
        candidates.insert(0, str(Path(base).with_suffix('.mp3')))
    candidates += [base] + [str(Path(base).with_suffix('.' + ext))
                            for ext in ('mp4', 'mkv', 'webm', 'm4a')]
    for path in candidates:
        if path and Path(path).is_file() and Path(path).stat().st_size > 0:
            return str(path)
    raise RuntimeError('Download finished but the output file is missing or empty.')
