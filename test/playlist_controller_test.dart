import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nazzelha/models/download_progress.dart';
import 'package:nazzelha/services/download_paths.dart';
import 'package:nazzelha/services/playlist_controller.dart';
import 'package:nazzelha/services/python_service.dart';
import 'package:nazzelha/screens/playlist_screen.dart';
import 'package:nazzelha/screens/playlist_history_screen.dart';
import 'package:nazzelha/theme/locale_provider.dart';

class PlaylistBackend extends PythonService {
  bool publicWeb = false;
  @override
  bool get isPublicWeb => publicWeb;
  final calls = <String>[];
  bool failSecond = true;
  PlaylistBackend() : super(logger: Logger(level: Level.off));

  @override
  Future<Map<String, dynamic>> getPlaylist(String url) async => {
        'success': true,
        'title': 'Lessons',
        'entries': [
          {'id': 'abcdefghijk', 'url': 'first', 'title': 'One', 'index': 1},
          {'id': '12345678901', 'url': 'second', 'title': 'Two', 'index': 2},
          {
            'id': 'private0000',
            'url': 'private',
            'unavailable': true,
            'index': 3
          },
        ],
      };

  @override
  Stream<DownloadProgress> downloadPlaylistEntry(
      String url, String folder) async* {
    calls.add('$folder/$url');
    if (url == 'second' && failSecond) throw Exception('Unavailable');
    yield DownloadProgress(
        percent: 50, speed: '', eta: '', totalBytes: 100, downloadedBytes: 50);
    lastDownloadResult = {'file': '$folder/$url.mp4'};
  }
}

class GatedPlaylistBackend extends PlaylistBackend {
  final started = Completer<void>();
  final gate = Completer<void>();
  bool cancelled = false;
  @override
  Future<void> cancelDownload() async {
    cancelled = true;
    if (!gate.isCompleted) gate.complete();
  }

  @override
  Stream<DownloadProgress> downloadPlaylistEntry(
      String url, String folder) async* {
    calls.add('$folder/$url');
    if (url == 'first') {
      started.complete();
      yield DownloadProgress(
          percent: 20,
          speed: '',
          eta: '',
          totalBytes: 100,
          downloadedBytes: 20);
      await gate.future;
      if (cancelled) throw DownloadCancelledException('Cancelled');
    }
    lastDownloadResult = {'file': '$folder/$url.mp4'};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('expired public playlist entry can be prepared again individually',
      () async {
    final python = PlaylistBackend()..publicWeb = true;
    final c = PlaylistController(python);
    await c.load();
    await c.extract('https://youtube.com/playlist?list=PL123');
    await c.start();
    final first = c.entries.first;
    final previousCalls = python.calls.length;
    c.expireWebFile(PlaylistController.entryKey(first));
    expect(c.entries.first['status'], 'failed');
    await c.resumeEntry(PlaylistController.entryKey(first));
    expect(c.entries.first['status'], 'completed');
    expect(python.calls.length, previousCalls + 1);
    c.dispose();
  });

  testWidgets('playlist page supports Arabic on a narrow mobile screen',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = PlaylistController(PlaylistBackend());
    await c.load();
    await c.extract('https://youtube.com/playlist?list=PL123');
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: c),
          Provider<PythonService>.value(value: c.python),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ],
        child: const MaterialApp(
            locale: Locale('ar'),
            supportedLocales: [Locale('ar'), Locale('en')],
            localizationsDelegates: [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            home: PlaylistScreen())));
    await tester.pumpAndSettle();
    expect(find.text('بلاي ليست يوتيوب'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.enterText(
        find.byKey(const ValueKey('playlist-folder')), 'دروسي');
    expect(c.folder, 'دروسي');
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  test('playlist validation rejects other hosts and missing list ids', () {
    expect(
        DownloadPaths.isYoutubePlaylist(
            'https://youtube.com/watch?v=abc&list=PL123'),
        isTrue);
    expect(DownloadPaths.isYoutubePlaylist('https://youtube.com/watch?v=abc'),
        isFalse);
    expect(
        DownloadPaths.isYoutubePlaylist(
            'https://youtube.com.evil.test/?list=PL123'),
        isFalse);
    expect(DownloadPaths.isYoutubePlaylist('https://facebook.com/?list=PL123'),
        isFalse);
  });

  test(
      'continues failures, keeps chosen folder and retries only remaining videos',
      () async {
    final backend = PlaylistBackend();
    final c = PlaylistController(backend);
    await c.load();
    await c.extract('https://youtube.com/playlist?list=PL123');
    c.setFolder('../دروس/Flutter');
    await c.start();
    expect(c.completed, 1);
    expect(c.job!['status'], 'partial');
    expect(backend.calls.length, 2);
    expect(c.folder, 'دروس Flutter');
    c.setFolder('different');
    expect(c.folder, 'دروس Flutter');
    backend.failSecond = false;
    await c.start();
    expect(c.completed, 2);
    expect(backend.calls,
        ['دروس Flutter/first', 'دروس Flutter/second', 'دروس Flutter/second']);
    expect(c.hasRemaining, isFalse);
    c.dispose();
  });

  test('restores interrupted playlist without declaring success', () async {
    final backend = PlaylistBackend();
    final c = PlaylistController(backend);
    await c.load();
    await c.extract('https://youtube.com/playlist?list=PL123');
    c.job!['status'] = 'running';
    c.setFolder('Saved');
    final prefs = await SharedPreferences.getInstance();
    // setFolder is locked during execution, so preserve through an actual saved snapshot.
    await prefs.setString(PlaylistController.prefsKey,
        '{"id":"saved","status":"running","folder":"Saved","entries":[{"status":"downloading"}]}');
    final restored = PlaylistController(backend);
    await restored.load();
    expect(restored.job!['status'], 'paused');
    expect(restored.entries.single['status'], 'paused');
    expect(backend.calls, isEmpty);
    c.dispose();
    restored.dispose();
  });
  test('history keeps multiple playlists and resumes only the requested video',
      () async {
    final backend = PlaylistBackend();
    final c = PlaylistController(backend);
    await c.load();
    await c.extract('https://youtube.com/playlist?list=PLfirst');
    final firstId = c.job!['id'].toString();
    await c.start();
    final failedKey = PlaylistController.entryKey(c.entries[1]);
    await c.extract('https://youtube.com/playlist?list=PLsecond');
    final secondId = c.job!['id'].toString();
    expect(c.history.length, 2);
    c.select(firstId);
    backend.failSecond = false;
    await c.resumeEntry(failedKey);
    expect(
        backend.calls, ['Lessons/first', 'Lessons/second', 'Lessons/second']);
    expect(c.completed, 2);
    c.select(secondId);
    expect(c.completed, 0);
    final removed = PlaylistController.entryKey(c.entries.first);
    await c.removeEntry(removed);
    await c.start();
    expect(backend.calls.last, 'Lessons/second');
    expect(backend.calls.where((call) => call == 'Lessons/first').length, 1);
    c.removeHistory(firstId);
    final restored = PlaylistController(backend);
    await restored.load();
    expect(restored.history.length, 1);
    expect(restored.job!['id'], secondId);
    expect(
        restored.entries.any((e) => PlaylistController.entryKey(e) == removed),
        isFalse);
    c.dispose();
    restored.dispose();
  });

  test('removing the active video cancels it and the remaining queue continues',
      () async {
    final backend = GatedPlaylistBackend();
    final c = PlaylistController(backend);
    await c.load();
    await c.extract('https://youtube.com/playlist?list=PLfirst');
    final key = PlaylistController.entryKey(c.entries.first);
    final run = c.start();
    await backend.started.future;
    await c.removeEntry(key);
    await run;
    expect(backend.cancelled, isTrue);
    expect(
        c.entries.any((e) => PlaylistController.entryKey(e) == key), isFalse);
    expect(c.completed, 1);
    expect(backend.calls, ['Lessons/first', 'Lessons/second']);
    await c.start();
    expect(backend.calls.length, 2);
    c.dispose();
  });
  testWidgets(
      'history shows playlist summaries and opens individual retry controls',
      (tester) async {
    final backend = PlaylistBackend();
    final c = PlaylistController(backend);
    await c.load();
    await c.extract('https://youtube.com/playlist?list=PL123');
    await c.start();
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider.value(value: c),
      Provider<PythonService>.value(value: backend),
      ChangeNotifierProvider(create: (_) => LocaleProvider()),
    ], child: const MaterialApp(home: PlaylistHistoryScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Lessons'), findsOneWidget);
    expect(find.text('1 downloaded · 2 remaining or stopped'), findsOneWidget);
    expect(find.text('One'), findsNothing);
    await tester.tap(find.text('Lessons'));
    await tester.pumpAndSettle();
    expect(find.byType(PlaylistScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('playlist-extract')), findsNothing);
    final retry = find
        .byKey(ValueKey('resume-${PlaylistController.entryKey(c.entries[1])}'));
    expect(c.canStart, isTrue, reason: c.history.toString());
    await tester.scrollUntilVisible(retry.hitTestable(), 150,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    backend.failSecond = false;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(c.completed, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
