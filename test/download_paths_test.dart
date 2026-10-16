import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nazzelha/services/download_paths.dart';

void main() {
  group('platformFolder', () {
    test('maps the four supported platforms', () {
      expect(DownloadPaths.platformFolder('youtube'), 'YouTube');
      expect(DownloadPaths.platformFolder('facebook'), 'Facebook');
      expect(DownloadPaths.platformFolder('instagram'), 'Instagram');
      expect(DownloadPaths.platformFolder('tiktok'), 'TikTok');
    });

    test('never derives a folder from raw URL text', () {
      // Unknown platform → generic sanitized name, not the URL content.
      final folder = DownloadPaths.platformFolder('https://evil.com/path');
      expect(folder.contains('evil.com'), isFalse);
    });
  });

  group('URL validation', () {
    test('accepts http/https only', () {
      expect(DownloadPaths.isUsableUrl('https://youtube.com/x'), isTrue);
      expect(DownloadPaths.isUsableUrl('ftp://youtube.com/x'), isFalse);
      expect(DownloadPaths.isUsableUrl(''), isFalse);
    });

    test('matches and detects platforms', () {
      expect(DownloadPaths.urlMatchesPlatform(
          'https://youtu.be/abc', 'youtube'), isTrue);
      expect(DownloadPaths.urlMatchesPlatform(
          'https://youtube.com/watch', 'facebook'), isFalse);
      expect(DownloadPaths.detectPlatform('https://fb.watch/xyz'), 'facebook');
      expect(DownloadPaths.detectPlatform('https://vt.tiktok.com/abc'), 'tiktok');
    });
  });

  group('sanitizeFilename', () {
    test('strips path separators and traversal', () {
      expect(DownloadPaths.sanitizeFilename('../..//etc/passwd'), 'etc passwd');
      expect(DownloadPaths.sanitizeFilename(r'..\..\windows\system32'),
          'windows system32');
      expect(DownloadPaths.sanitizeFilename('..'), '');
    });

    test('strips invalid filesystem characters', () {
      final name = DownloadPaths.sanitizeFilename('a<b>:c|d?e*f"g');
      expect(name, 'a b c d e f g');
    });

    test('guards reserved Windows device names', () {
      expect(DownloadPaths.sanitizeFilename('CON'), '_CON');
      expect(DownloadPaths.sanitizeFilename('aux.mp4'), '_aux.mp4');
    });

    test('removes trailing dots and spaces', () {
      expect(DownloadPaths.sanitizeFilename('hello...  '), 'hello');
    });

    test('returns empty for unusable input', () {
      expect(DownloadPaths.sanitizeFilename('   '), '');
      expect(DownloadPaths.sanitizeFilename('///'), '');
    });
  });

  group('ensureExtension', () {
    test('appends missing extension per mode', () {
      expect(DownloadPaths.ensureExtension('clip', 'video'), 'clip.mp4');
      expect(DownloadPaths.ensureExtension('song', 'audio'), 'song.mp3');
    });

    test('does not duplicate the correct extension', () {
      expect(DownloadPaths.ensureExtension('clip.mp4', 'video'), 'clip.mp4');
      expect(DownloadPaths.ensureExtension('song.MP3', 'audio'), 'song.MP3');
    });

    test('replaces a wrong media extension', () {
      expect(DownloadPaths.ensureExtension('clip.webm', 'video'), 'clip.mp4');
      expect(DownloadPaths.ensureExtension('song.mp4', 'audio'), 'song.mp3');
    });
  });

  group('resolveOutputFilename', () {
    test('falls back to sanitized fallback when empty', () {
      final name = DownloadPaths.resolveOutputFilename(
          rawName: '', mode: 'video', fallbackName: 'My Video');
      expect(name, 'My Video.mp4');
    });

    test('resolves conflicts against an existing directory', () {
      final dir = Directory.systemTemp.createTempSync('nazzelha_test_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}${Platform.pathSeparator}clip.mp4')
          .writeAsStringSync('x');
      final name = DownloadPaths.resolveOutputFilename(
        rawName: 'clip.mp4',
        mode: 'video',
        fallbackName: 'clip',
        directory: dir.path,
      );
      expect(name, 'clip (1).mp4');
    });
  });
}
