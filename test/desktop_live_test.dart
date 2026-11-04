import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nazzelha/services/playlist_controller.dart';
import 'package:nazzelha/services/python_service.dart';
import 'package:nazzelha/services/runtime_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const live = bool.fromEnvironment('LIVE_MEDIA_TESTS');
  test('Windows cancellation releases the worker and the next command succeeds',
      () async {
    final python = PythonService(logger: Logger(level: Level.off));
    StreamSubscription? subscription;
    Future<void>? cancellation;
    final terminal = Completer<void>();
    try {
      await python.initialize();
      final output = Directory('build/cancel_acceptance')
        ..createSync(recursive: true);
      subscription = python
          .downloadVideo('https://www.facebook.com/share/v/14ub8NMwKXx/',
              'facebook', 4320, output.absolute.path)
          .listen((progress) {
        if (progress.downloadedBytes > 0 && cancellation == null) {
          cancellation = python.cancelDownload();
        }
      }, onError: (Object error, StackTrace stack) {
        if (terminal.isCompleted) return;
        if (error is DownloadCancelledException) {
          terminal.complete();
        } else {
          terminal.completeError(error, stack);
        }
      }, onDone: () {
        if (!terminal.isCompleted) {
          terminal.completeError(
              StateError('Download completed before cancellation'));
        }
      });
      await terminal.future.timeout(const Duration(minutes: 3));
      await cancellation;
      expect(python.isInitialized, isTrue);
      expect(await python.getDownloadDirectory(), isNotEmpty);
    } finally {
      await subscription?.cancel();
      await python.dispose();
    }
  },
      skip: !live || kIsWeb || !RuntimePlatform.isWindows,
      timeout: const Timeout(Duration(minutes: 4)));
  test('Windows engine downloads the playlist to the selected folder',
      () async {
    SharedPreferences.setMockInitialValues({});
    final python = PythonService(logger: Logger(level: Level.off));
    final c = PlaylistController(python);
    try {
      await python.initialize();
      expect(python.isInitialized, isTrue);
      await c.load();
      await c.extract('https://youtube.com/playlist?list=PLPqyWmL4W9D0');
      expect(c.entries.length, 3);
      const folder = 'اختبار نزلها — Windows';
      c.setFolder(folder);
      await c.start();
      expect(c.completed, 3, reason: c.entries.toString());
      for (final entry in c.entries) {
        final file = File(entry['file'] as String);
        expect(file.parent.uri.pathSegments.where((p) => p.isNotEmpty).last,
            folder);
        expect(file.existsSync(), isTrue);
        expect(file.lengthSync(), greaterThan(0));
      }
    } finally {
      c.dispose();
      await python.dispose();
    }
  },
      skip: !live || kIsWeb || !RuntimePlatform.isWindows,
      timeout: const Timeout(Duration(minutes: 20)));
}
