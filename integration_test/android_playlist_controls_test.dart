import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:logger/logger.dart';
import 'package:nazzelha/services/python_service.dart';
import 'package:nazzelha/services/playlist_controller.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native single-entry retry, removal, history and folder opening',
      (tester) async {
    final python = PythonService(logger: Logger(level: Level.off));
    await python.initialize();
    expect(python.isInitialized, isTrue);
    final id = 'controls_${DateTime.now().microsecondsSinceEpoch}';
    final job = <String, dynamic>{
      'id': id,
      'title': 'Native controls',
      'folder': 'اختبار المسار',
      'status': 'ready',
      'only_entry': '2:b',
      'entries': [
        for (final spec in [(1, 'a'), (2, 'b'), (3, 'c')])
          {
            'key': '${spec.$1}:${spec.$2}',
            'index': spec.$1,
            'id': spec.$2,
            'title': spec.$2,
            'url': 'https://example.invalid/${spec.$2}',
            'status': 'pending'
          },
      ],
    };
    // Persist removal before starting a stale snapshot: it must still be skipped.
    await python.removeNativePlaylistEntry(id, '1:a');
    await python.startNativePlaylist(job);
    Future<Map<String, dynamic>> waitForTerminal() async {
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      Map<String, dynamic>? saved;
      do {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        saved = await python.getNativePlaylist();
      } while (
          saved?['status'] == 'running' && DateTime.now().isBefore(deadline));
      expect(saved?['status'], isNot('running'));
      return saved!;
    }

    final first = await waitForTerminal();
    final entries = first['entries'] as List;
    expect(entries[0]['removed'], isTrue);
    expect(entries[1]['status'], 'failed');
    expect(entries[2]['status'], 'pending');
    final c = PlaylistController(python);
    await c.load();
    c.select(id);
    (c.job!['entries'] as List)[1]['status'] = 'paused';
    await c.resumeEntry('3:c');
    final second = await waitForTerminal();
    expect((second['entries'] as List)[0]['removed'], isTrue);
    expect((second['entries'] as List)[1]['status'], 'paused');
    expect((second['entries'] as List)[2]['status'], 'failed');
    await c.refreshNative();
    c.removeHistory(id);
    await c.refreshNative();
    expect(c.history.any((j) => j['id'] == id), isFalse);
    await python.openDownloadLocation(folder: 'اختبار المسار');
    c.dispose();
    await python.dispose();
  }, timeout: const Timeout(Duration(minutes: 4)));
}
