import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nazzelha/services/playlist_controller.dart';
import 'package:nazzelha/services/python_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'iOS hosted metadata and disk download preserve Unicode playlist folder',
      (tester) async {
    expect(Platform.isIOS, isTrue,
        reason: 'Run this integration test on an iOS simulator.');
    String? saved;
    await tester.runAsync(() async {
      final bytes = List<int>.generate(4099, (i) => i % 251);
      final commands = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8127);
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path.endsWith('/health')) {
          request.response
              .write(jsonEncode({'ready': true, 'transfer': 'browser'}));
        } else {
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          if (request.uri.path.endsWith('/command')) {
            commands.add(body['action'].toString());
            request.response.write(jsonEncode({
              'success': true,
              'qualities': [360, 720]
            }));
          } else {
            for (final event in [
              {
                'event': 'file_start',
                'filename': 'فيديو.mp4',
                'size': bytes.length
              },
              {
                'event': 'file_chunk',
                'data': base64Encode(bytes.sublist(0, 1000))
              },
              {
                'event': 'file_chunk',
                'data': base64Encode(bytes.sublist(1000))
              },
              {'success': true, 'transfer': 'browser', 'filename': 'فيديو.mp4'},
            ]) {
              request.response.writeln(jsonEncode(event));
            }
          }
        }
        await request.response.close();
      });
      final service = PythonService(logger: Logger(level: Level.off));
      try {
        await service.initialize();
        expect(service.isInitialized, isTrue);
        expect(
            await service.getAvailableQualities(
                'https://youtube.com/watch?v=abcdefghijk', 'youtube'),
            [360, 720]);
        await service
            .downloadPlaylistEntry(
                'https://youtube.com/watch?v=abcdefghijk', 'تجربة عربية')
            .drain<void>();
        saved = service.lastDownloadResult!['file'] as String;
        expect(saved, contains('/Playlists/تجربة عربية/'));
        expect(await File(saved!).readAsBytes(), bytes);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            PlaylistController.historyKey,
            jsonEncode([
              {
                'id': 'ios-smoke',
                'folder': 'تجربة عربية',
                'status': 'completed',
                'entries': [
                  {
                    'id': 'abcdefghijk',
                    'index': 1,
                    'status': 'completed',
                    'file': saved
                  }
                ]
              }
            ]));
        final history = PlaylistController(service);
        try {
          await history.load();
          expect(history.error, isNull);
          expect(history.completed, 1);
          expect(commands, ['get_qualities'],
              reason:
                  'iOS must not send desktop folder repair commands to the hosted API.');
        } finally {
          history.dispose();
          await prefs.clear();
        }
      } finally {
        await service.dispose();
        await server.close(force: true);
        if (saved != null) await File(saved!).delete();
      }
    });
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Center(
                child: Text('iOS HTTP and Unicode file transfer passed')))));
    await tester.pump();
  });
}
