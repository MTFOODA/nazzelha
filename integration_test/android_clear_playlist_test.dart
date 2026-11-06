import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nazzelha/services/playlist_controller.dart';
import 'package:nazzelha/services/python_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('cleared playlist stays empty through native polling and restart',
      (tester) async {
    expect(Platform.isAndroid, isTrue);
    expect(const bool.fromEnvironment('ANDROID_CI_ISOLATED'), isTrue,
        reason:
            'Run only in the isolated CI emulator, never on a personal phone.');
    final python = PythonService(logger: Logger(level: Level.off));
    final id = 'clear_ci_${DateTime.now().microsecondsSinceEpoch}';
    File? fixture;
    PlaylistController? first;
    PlaylistController? restored;
    try {
      await python.initialize();
      expect(python.isInitialized, isTrue, reason: python.lastInitError);
      final cache = await getTemporaryDirectory();
      fixture = File('${cache.path}/$id.txt');
      await fixture.writeAsString('Fixture bytes, not downloaded media.');
      // A completed fixture avoids accessing YouTube or downloading real media.
      await python.startNativePlaylist({
        'id': id,
        'title': 'Clear CI',
        'folder': 'Clear CI',
        'status': 'ready',
        'entries': [
          {
            'key': '1:abcdefghijk',
            'index': 1,
            'id': 'abcdefghijk',
            'title': 'Fixture',
            'url': 'https://www.youtube.com/watch?v=abcdefghijk',
            'status': 'completed',
            'progress': 100,
            'file': fixture.path,
          }
        ],
      });
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      Map<String, dynamic>? native;
      do {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        native = await python.getNativePlaylist();
      } while (!['completed', 'failed', 'partial', 'paused']
              .contains(native?['status']) &&
          DateTime.now().isBefore(deadline));
      expect(native?['status'], 'completed');
      first = PlaylistController(python);
      await first.load();
      expect(first.job?['id'], id);
      expect(first.clearCurrent(), isTrue);
      await Future<void>.delayed(const Duration(seconds: 2));
      await first.refreshNative();
      expect(first.job, isNull);
      first.dispose();
      first = null;
      restored = PlaylistController(python);
      await restored.load();
      await restored.refreshNative();
      expect(restored.job, isNull);
      expect(restored.history.any((entry) => entry['id'] == id), isTrue);
      expect(
          await fixture.readAsString(), 'Fixture bytes, not downloaded media.');
      restored.select(id);
      expect(restored.completed, 1);
      expect(restored.entries.single['file'], fixture.path);
    } finally {
      first?.dispose();
      restored?.dispose();
      await python.dispose();
      if (fixture != null && fixture.existsSync()) await fixture.delete();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
