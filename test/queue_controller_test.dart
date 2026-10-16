import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:nazzelha/models/download_progress.dart';
import 'package:nazzelha/models/download_task.dart';
import 'package:nazzelha/services/python_service.dart';
import 'package:nazzelha/services/queue_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A controlled stand-in for [PythonService] so the queue engine can be tested
/// without a real backend or an Android device.
class FakePythonService extends PythonService {
  final List<String> downloadedUrls = [];
  final Set<String> failUrls = {};
  int cancelCount = 0;

  FakePythonService() : super(logger: Logger(level: Level.off));

  @override
  Future<String> getPlatformDownloadDirectory(String platform) async =>
      Directory.systemTemp.path;

  @override
  Future<Map<String, dynamic>?> getActiveDownload() async => null;

  @override
  Future<void> saveQueueSnapshot(List<Map<String, dynamic>> tasks) async {}

  @override
  Future<List<Map<String, dynamic>>?> getQueueSnapshot() async => null;

  @override
  Future<void> cancelDownload() async {
    cancelCount++;
  }

  @override
  Stream<DownloadProgress> downloadVideo(
    String url,
    String platform,
    int quality,
    String outputPath, {
    String mode = 'video',
    bool resume = false,
    String? filename,
  }) async* {
    downloadedUrls.add(url);
    if (failUrls.contains(url)) {
      throw Exception('simulated download failure');
    }
    yield DownloadProgress(
      percent: 50,
      speed: '1MiB/s',
      eta: '00:01',
      totalBytes: 100,
      downloadedBytes: 50,
      phase: 'downloading',
    );
    yield DownloadProgress(
      percent: 100,
      speed: 'N/A',
      eta: '00:00',
      totalBytes: 100,
      downloadedBytes: 100,
      phase: 'merging',
    );
    lastDownloadResult = {
      'file': '$outputPath${Platform.pathSeparator}out_${downloadedUrls.length}.mp4',
      'filename': 'out.mp4',
    };
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  NazzelhaQueueController makeController(FakePythonService fake) {
    return NazzelhaQueueController(
      python: fake,
      logger: Logger(level: Level.off),
    );
  }

  DownloadTask addConfigured(
      NazzelhaQueueController c, String url, String platform) {
    final task = c.addTask();
    c.updateUrl(task.id, url);
    c.updatePlatform(task.id, platform);
    return task;
  }

  test('tasks without Start are skipped by the queue', () async {
    final fake = FakePythonService();
    final c = makeController(fake);

    final approved = addConfigured(c, 'https://youtube.com/a', 'youtube');
    addConfigured(c, 'https://youtube.com/b', 'youtube'); // never approved

    await c.start(approved.id);
    await pumpUntilIdle(c);

    expect(fake.downloadedUrls, ['https://youtube.com/a']);
    expect(c.tasks.firstWhere((t) => t.url.endsWith('/b')).status,
        TaskStatus.pending);
  });

  test('runs approved tasks strictly sequentially in approval order', () async {
    final fake = FakePythonService();
    final c = makeController(fake);

    final a = addConfigured(c, 'https://youtube.com/a', 'youtube');
    final b = addConfigured(c, 'https://facebook.com/b', 'facebook');
    final c3 = addConfigured(c, 'https://instagram.com/c', 'instagram');

    await Future.wait([c.start(a.id), c.start(b.id), c.start(c3.id)]);
    await pumpUntilIdle(c);

    expect(fake.downloadedUrls, [
      'https://youtube.com/a',
      'https://facebook.com/b',
      'https://instagram.com/c',
    ]);
    for (final t in c.tasks) {
      expect(t.status, TaskStatus.completed);
    }
  });

  test('duplicate start taps do not create duplicate downloads', () async {
    final fake = FakePythonService();
    final c = makeController(fake);

    final a = addConfigured(c, 'https://youtube.com/a', 'youtube');
    await c.start(a.id);
    await c.start(a.id);
    await c.start(a.id);
    await pumpUntilIdle(c);

    expect(
        fake.downloadedUrls.where((u) => u == 'https://youtube.com/a').length, 1);
  });

  test('a failing task is recorded and the next eligible task still runs', () async {
    final fake = FakePythonService();
    final c = makeController(fake);

    final a = addConfigured(c, 'https://youtube.com/a', 'youtube');
    final b = addConfigured(c, 'https://youtube.com/b', 'youtube');
    fake.failUrls.add('https://youtube.com/a');

    await Future.wait([c.start(a.id), c.start(b.id)]);
    await pumpUntilIdle(c);

    expect(fake.downloadedUrls, [
      'https://youtube.com/a',
      'https://youtube.com/b',
    ]);
    expect(c.tasks.firstWhere((t) => t.url.endsWith('/a')).status, TaskStatus.failed);
    expect(
        c.tasks.firstWhere((t) => t.url.endsWith('/b')).status, TaskStatus.completed);
  });

  test('removing a pending task does not corrupt ordering', () async {
    final fake = FakePythonService();
    final c = makeController(fake);

    final a = addConfigured(c, 'https://youtube.com/a', 'youtube');
    final b = addConfigured(c, 'https://youtube.com/b', 'youtube');
    final c3 = addConfigured(c, 'https://youtube.com/c', 'youtube');

    await c.remove(b.id); // remove the middle one before approval

    await Future.wait([c.start(a.id), c.start(c3.id)]);
    await pumpUntilIdle(c);

    expect(fake.downloadedUrls, [
      'https://youtube.com/a',
      'https://youtube.com/c',
    ]);
  });

  test('invalid cross-platform URL is rejected with a stable error code', () async {
    final fake = FakePythonService();
    final c = makeController(fake);

    final t = addConfigured(c, 'https://facebook.com/x', 'youtube');
    final error = await c.start(t.id);

    expect(error, QueueErrorCodes.crossPlatform);
    expect(t.errorDetail, 'facebook');
    expect(t.status, TaskStatus.pending);
    expect(fake.downloadedUrls, isEmpty);
  });

  test('model JSON round-trip preserves state', () {
    final task = DownloadTask(
      id: 't1',
      url: 'https://youtube.com/x',
      platform: 'youtube',
      mode: 'audio',
      filename: 'my song.mp3',
      status: TaskStatus.queued,
      progress: 42,
      progressKnown: true,
      sequence: 3,
    );
    final restored = DownloadTask.fromJson(task.toJson());
    expect(restored.id, 't1');
    expect(restored.status, TaskStatus.queued);
    expect(restored.mode, 'audio');
    expect(restored.sequence, 3);
  });

  test('recovery marks in-flight tasks as paused on load', () async {
    SharedPreferences.setMockInitialValues({
      NazzelhaQueueController.prefsKey:
          '[{"id":"t1","url":"https://youtube.com/a","platform":"youtube",'
              '"mode":"video","filename":"","status":"downloading","progress":30,'
              '"progressKnown":true,"sequence":1},'
              '{"id":"t2","url":"https://youtube.com/b","platform":"youtube",'
              '"mode":"video","filename":"","status":"pending","progress":0,'
              '"progressKnown":false,"sequence":null}]',
    });
    final fake = FakePythonService();
    final c = makeController(fake);
    await c.load();

    final t1 = c.tasks.firstWhere((t) => t.id == 't1');
    final t2 = c.tasks.firstWhere((t) => t.id == 't2');
    expect(t1.status, TaskStatus.paused);
    expect(t2.status, TaskStatus.pending);
  });

  test('recovery auto-resumes approved-but-not-started (queued) tasks', () async {
    SharedPreferences.setMockInitialValues({
      NazzelhaQueueController.prefsKey:
          '[{"id":"t1","url":"https://youtube.com/a","platform":"youtube",'
              '"mode":"video","filename":"","status":"queued","progress":0,'
              '"progressKnown":false,"sequence":1}]',
    });
    final fake = FakePythonService();
    final c = makeController(fake);
    await c.load();
    await pumpUntilIdle(c);

    expect(fake.downloadedUrls, ['https://youtube.com/a']);
    expect(c.tasks.firstWhere((t) => t.id == 't1').status, TaskStatus.completed);
  });

  test('recovery does NOT auto-resume an interrupted (paused) task', () async {
    SharedPreferences.setMockInitialValues({
      NazzelhaQueueController.prefsKey:
          '[{"id":"t1","url":"https://youtube.com/a","platform":"youtube",'
              '"mode":"video","filename":"","status":"paused","progress":30,'
              '"progressKnown":true,"sequence":1}]',
    });
    final fake = FakePythonService();
    final c = makeController(fake);
    await c.load();
    await pumpUntilIdle(c);

    expect(fake.downloadedUrls, isEmpty);
    expect(c.tasks.firstWhere((t) => t.id == 't1').status, TaskStatus.paused);
  });
}

/// Pump microtasks/timers until the queue's execution loop settles.
Future<void> pumpUntilIdle(NazzelhaQueueController c) async {
  for (var i = 0; i < 100 && c.isExecuting; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}
