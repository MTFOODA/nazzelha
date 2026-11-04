import 'package:flutter_driver/flutter_driver.dart';
import 'dart:io';

Future<void> main() async {
  final driver = await FlutterDriver.connect();
  try {
    await driver.runUnsynchronized(() async {
      await driver.tap(find.text('Playlist'));
      await driver.tap(find.byValueKey('playlist-url'));
      await driver.enterText('https://youtube.com/playlist?list=PLPqyWmL4W9D0');
      await driver.tap(find.byValueKey('playlist-extract'));
      await driver.waitFor(find.byValueKey('playlist-folder'),
          timeout: const Duration(minutes: 5));
      await driver.tap(find.byValueKey('playlist-folder'));
      await driver.enterText('Windows Acceptance');
      await driver.tap(find.byValueKey('playlist-download'));
      await driver.waitFor(find.text('3 of 3 downloaded'),
          timeout: const Duration(minutes: 15));
      stdout.writeln('WINDOWS_ACCEPTANCE_PASSED completed=3');
    });
  } finally {
    await driver.close();
  }
}
