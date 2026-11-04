import 'package:integration_test/integration_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nazzelha/screens/playlist_screen.dart';
import 'package:nazzelha/services/playlist_controller.dart';
import 'package:nazzelha/services/python_service.dart';
import 'package:nazzelha/theme/locale_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const live = bool.fromEnvironment('LIVE_MEDIA_TESTS');
  testWidgets(
      'Edge: real playlist extraction, folder choice and best-quality downloads',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final python = PythonService(logger: Logger(level: Level.off));
    await tester.runAsync(python.initialize);
    expect(python.isInitialized, isTrue, reason: python.lastInitError);
    final controller = PlaylistController(python);
    await tester.runAsync(controller.load);
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider.value(value: controller),
      ChangeNotifierProvider(create: (_) => LocaleProvider()),
    ], child: const MaterialApp(home: PlaylistScreen())));
    await tester.pumpAndSettle();
    expect(find.text('YouTube playlist'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first,
        'https://youtube.com/playlist?list=PLPqyWmL4W9D0&si=VJuyQm3_tCJb2XDj');
    await tester.tap(find.text('Extract videos'));
    await tester.runAsync(() async {
      while (controller.loading) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    });
    await tester.pumpAndSettle();
    expect(controller.error, isNull);
    expect(controller.entries.length, 3);
    await tester.enterText(find.byKey(const ValueKey('playlist-folder')), 'Edge Acceptance');
    await tester.pump();
    expect(controller.folder, 'Edge Acceptance');
    await tester.runAsync(controller.start);
    await tester.pumpAndSettle();
    expect(controller.entries.where((e) => e['status'] != 'completed'), isEmpty,
        reason: controller.entries.toString());
    expect(controller.completed, 3);
    expect(
        controller.entries
            .every((e) => e['file'].toString().contains('Edge Acceptance')),
        isTrue);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await python.dispose();
    debugPrint('EDGE_ACCEPTANCE_PASSED completed=3');
  }, skip: !kIsWeb || !live, timeout: const Timeout(Duration(minutes: 15)));
}
