import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from download_location import open_download_location


class LocationTests(unittest.TestCase):
    def test_opens_arabic_folder_and_reveals_download_without_shell(self):
        with tempfile.TemporaryDirectory() as tmp, patch('download_location.subprocess.Popen') as launch:
            root = Path(tmp)
            folder = root / 'YouTube/Playlists/دروسي'
            folder.mkdir(parents=True)
            file = folder / 'فيديو.mp4'
            file.write_bytes(b'media')
            self.assertTrue(open_download_location({'folder': 'دروسي'}, root)['success'])
            self.assertIn(str(folder), launch.call_args.args[0])
            open_download_location({'file': str(file)}, root)
            self.assertNotIn('shell', launch.call_args.kwargs)
            self.assertEqual(launch.call_count, 2)

    def test_rejects_traversal_and_existing_files_outside_download_root(self):
        with tempfile.TemporaryDirectory() as tmp, patch('download_location.subprocess.Popen') as launch:
            root = Path(tmp) / 'downloads'
            root.mkdir()
            outside = Path(tmp) / 'outside.mp4'
            outside.write_bytes(b'media')
            with self.assertRaises(ValueError):
                open_download_location({'file': str(outside)}, root)
            with self.assertRaises(ValueError):
                open_download_location({'folder': '../outside'}, root)
            launch.assert_not_called()
