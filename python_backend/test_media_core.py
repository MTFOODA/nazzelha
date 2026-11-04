import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

import yt_dlp

from media_core import extract_media, extract_playlist, final_filepath, playlist_url, valid_url
from media_core import extraction_options
import media_core


class MediaCoreTests(unittest.TestCase):
    def test_cancelled_download_stops_at_the_next_progress_hook(self):
        from downloader import VideoDownloader
        downloader = VideoDownloader()
        downloader._stop_download = True
        with self.assertRaises(yt_dlp.utils.DownloadError):
            downloader._progress_hook({'status': 'downloading'})

    def test_repairs_only_known_garbled_folder_without_overwriting_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'Playlists'
            folder = 'اناشيد عامة'
            alias = root / folder.encode('utf-8').decode('cp1252')
            alias.mkdir(parents=True)
            src = alias / 'lesson.mp4'
            src.write_bytes(b'downloaded media')
            destination = root / folder
            destination.mkdir()
            existing = destination / 'lesson.mp4'
            existing.write_bytes(b'existing media')
            other = root / 'Other'
            other.mkdir()
            unrelated = other / 'other.mp4'
            unrelated.write_bytes(b'untouched')
            result = media_core.repair_playlist_folder(root, folder, [str(src), str(unrelated)])
            self.assertEqual(existing.read_bytes(), b'existing media')
            self.assertEqual(Path(result['files'][str(src)]).read_bytes(), b'downloaded media')
            self.assertEqual(Path(result['files'][str(src)]).parent, destination)
            self.assertEqual(unrelated.read_bytes(), b'untouched')
            self.assertFalse(alias.exists())
            with self.assertRaises(ValueError):
                media_core.repair_playlist_folder(root, '../escape', [str(unrelated)])

    def test_session_import_is_scoped_persistent_and_removable(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(media_core, '_cookie_directory', Path(tmp)):
            content = ('# Netscape HTTP Cookie File\n'
                       '.facebook.com\tTRUE\t/\tTRUE\t0\tc_user\ttest-only-value\n'
                       '.instagram.com\tTRUE\t/\tTRUE\t0\tsessionid\tother-platform\n')
            result = media_core.configure_auth({'platform': 'facebook', 'content': content})
            self.assertTrue(result['platforms']['facebook'])
            saved = media_core.cookie_path('facebook').read_text()
            self.assertNotIn('instagram.com', saved)
            self.assertNotIn('test-only-value', str(result))
            self.assertIn('cookiefile', extraction_options('facebook'))
            self.assertNotIn('cookiefile', extraction_options('instagram'))
            media_core.configure_auth({'platform': 'facebook'})
            self.assertNotIn('cookiefile', extraction_options('facebook'))
            with self.assertRaises(ValueError):
                media_core.configure_auth({'platform': 'facebook', 'content': 'invalid text'})

    def test_direct_https_wins_at_same_resolution_without_lowering_resolution(self):
        for hls_height, expected in ((1080, '399+251'), (2160, '616+251')):
            opts = extraction_options('youtube')
            opts['format'] = 'bestvideo+bestaudio/best'
            opts['quiet'] = True
            formats = [
                dict(format_id='616', url='https://media.example/a.m3u8',
                     protocol='m3u8_native', ext='mp4', height=hls_height, fps=30,
                     vcodec='avc1', acodec='none', tbr=5000, quality=10),
                dict(format_id='399', url='https://media.example/video.mp4',
                     protocol='https', ext='mp4', height=1080, fps=30,
                     vcodec='av01', acodec='none', tbr=3000, quality=1),
                dict(format_id='251', url='https://media.example/audio.webm',
                     protocol='https', ext='webm', vcodec='none', acodec='opus', abr=160),
            ]
            with yt_dlp.YoutubeDL(opts) as ydl:
                result = ydl.process_ie_result(dict(id='test', title='test', formats=formats), download=False)
            self.assertEqual(result['format_id'], expected)

    def test_platform_host_validation(self):
        self.assertTrue(valid_url('https://www.facebook.com/share/v/abc/', 'facebook'))
        for url in ('https://facebook.com.evil.test/video', 'https://evil.test/?facebook.com',
                    'https://facebook.com@evil.test/', 'file:///youtube.com/video'):
            self.assertFalse(valid_url(url, 'facebook'))

    def test_playlist_is_youtube_only_and_normalizes_watch_links(self):
        self.assertEqual(playlist_url('https://youtu.be/abcdefghijk?list=PL123&si=tracking'),
                         'https://www.youtube.com/playlist?list=PL123')
        for url in ('https://facebook.com/watch?list=PL123',
                    'https://youtube.com/playlist', 'https://youtube.com.evil.test/?list=PL123'):
            with self.assertRaises(ValueError):
                playlist_url(url)

    def test_facebook_share_retries_same_video_canonical_url(self):
        ydl = MagicMock()
        ydl.extract_info.side_effect = [yt_dlp.utils.DownloadError('[facebook] 123456: Cannot parse data'),
                                       {'id': '123456', 'formats': [{}]}]
        self.assertEqual(extract_media(ydl, 'https://facebook.com/share/v/token/', 'facebook')['id'], '123456')
        self.assertEqual(ydl.extract_info.call_args.args[0], 'https://www.facebook.com/watch/?v=123456')

    def test_transfer_errors_are_not_replayed(self):
        ydl = MagicMock()
        ydl.extract_info.side_effect = yt_dlp.utils.DownloadError('HTTP Error 403')
        with self.assertRaises(yt_dlp.utils.DownloadError):
            extract_media(ydl, 'https://facebook.com/watch?v=123456', 'facebook', True)
        self.assertEqual(ydl.extract_info.call_count, 1)

    @patch('media_core.yt_dlp.YoutubeDL')
    def test_playlist_preserves_order_duplicates_and_unavailable_entries(self, factory):
        factory.return_value.__enter__.return_value.extract_info.return_value = {
            'title': 'Lessons', 'entries': [
                {'id': 'abcdefghijk', 'title': 'First'}, None,
                {'id': 'abcdefghijk', 'title': 'Again'},
                {'id': '12345678901', 'availability': 'private'}]}
        result = extract_playlist('https://youtube.com/playlist?list=PL123')
        self.assertEqual([e['index'] for e in result['entries']], [1, 3, 4])
        self.assertTrue(result['entries'][-1]['unavailable'])
        self.assertEqual(result['unavailable'], 1)

    def test_reports_merged_file_instead_of_premerge_template(self):
        with tempfile.TemporaryDirectory() as tmp:
            produced = Path(tmp) / 'video.mp4'
            produced.write_bytes(b'media')
            ydl = MagicMock()
            ydl.prepare_filename.return_value = str(Path(tmp) / 'video.webm')
            self.assertEqual(final_filepath(ydl, {}), str(produced))
            produced.unlink()
            with self.assertRaises(RuntimeError):
                final_filepath(ydl, {})


if __name__ == '__main__':
    unittest.main()
