import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:logger/logger.dart';
import 'package:nazzelha/services/playlist_controller.dart';
import 'package:nazzelha/services/python_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'Android playlist finishes all videos with the activity in background',
      (tester) async {
    final python = PythonService(logger: Logger(level: Level.off));
    await python.initialize();
    expect(python.isInitialized, isTrue, reason: python.lastInitError);
    const proxy = String.fromEnvironment('ANDROID_TEST_PROXY');
    if (proxy.isNotEmpty) {
      await const MethodChannel('nazzelha/python')
          .invokeMethod('debug_set_proxy', {'proxy': proxy});
    }
    final c = PlaylistController(python);
    await c.load();
    if (c.job?['url'] != 'https://youtube.com/playlist?list=PLPqyWmL4W9D0' ||
        c.folder != 'Android Acceptance') {
      await c.extract('https://youtube.com/playlist?list=PLPqyWmL4W9D0');
    }
    expect(c.error, isNull);
    expect(c.entries.length, 3);
    c.setFolder('Android Acceptance');
    await c.start();
    expect(c.error, isNull);
    await const MethodChannel('nazzelha/python')
        .invokeMethod('debug_background');
    final deadline = DateTime.now().add(const Duration(minutes: 30));
    do {
      await Future<void>.delayed(const Duration(seconds: 2));
      await c.refreshNative();
    } while (c.running && DateTime.now().isBefore(deadline));
    expect(c.running, isFalse);
    expect(c.entries.where((e) => e['status'] != 'completed'), isEmpty,
        reason: c.entries.toString());
    expect(c.completed, 3);
    expect(
        c.entries.every((e) => e['file'].toString().startsWith('content://')),
        isTrue);
    c.dispose();
    await python.dispose();
  }, timeout: const Timeout(Duration(minutes: 32)));
}
