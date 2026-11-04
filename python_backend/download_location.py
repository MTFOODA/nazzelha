"""Open only app-owned download locations on the local bridge computer."""
import os
import subprocess
import sys
from pathlib import Path


def open_download_location(command, root):
    root = Path(root).resolve()
    file = command.get('file')
    if file:
        target = Path(file).resolve()
        if not target.is_file():
            raise ValueError('The downloaded file could not be found.')
    else:
        platforms = dict(youtube='YouTube', facebook='Facebook', instagram='Instagram', tiktok='TikTok')
        platform = command.get('platform', 'youtube')
        if platform not in platforms:
            raise ValueError('Unsupported platform')
        target = root / platforms[platform]
        folder = command.get('folder')
        if folder is not None:
            if not folder or folder in ('.', '..') or any(c in folder for c in '/\\:'):
                raise ValueError('Invalid playlist folder name')
            target = target / 'Playlists' / folder
        target = target.resolve()
        if not target.is_dir():
            raise ValueError('The download folder could not be found.')
    if not target.is_relative_to(root) or target == root:
        raise ValueError('Invalid download location.')
    if os.name == 'nt':
        args = ['explorer.exe'] + (['/select,', str(target)] if file else [str(target)])
    elif sys.platform == 'darwin':
        args = ['open'] + (['-R', str(target)] if file else [str(target)])
    else:
        args = ['xdg-open', str(target.parent if file else target)]
    subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {'success': True}
