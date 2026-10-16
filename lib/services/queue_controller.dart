import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/download_task.dart';
import 'download_paths.dart';
import 'python_service.dart';

/// Sequential download queue engine for Nazzelha Sawa.
///
/// The controller is the single source of truth for queue *configuration* and
/// drives strict one-at-a-time execution. Each download itself is owned by the
/// existing Android foreground service (via [PythonService.downloadVideo]), so
/// the queue keeps running while the app is backgrounded or the screen is off.
///
/// Design invariants:
///  * Only one task may be active at a time (a single `_executing` loop).
///  * The visual list order (newest first) is independent of execution order
///    (approval [DownloadTask.sequence]).
///  * Start/Resume/Remove are idempotent; duplicate approvals are rejected.
///  * A task removed while active is never recreated by late events.
class NazzelhaQueueController extends ChangeNotifier {
  static const String prefsKey = 'nazzelha_sawa_queue';

  final PythonService _python;
  final Logger _logger;
  final List<DownloadTask> _tasks = [];

  int _idCounter = 0;
  int _seqCounter = 1;
  String? _activeTaskId;
  bool _executing = false;
  bool _disposed = false;
  SharedPreferences? _prefs;
  DateTime? _lastProgressPersist;

  NazzelhaQueueController({
    required PythonService python,
    required Logger logger,
  })  : _python = python,
        _logger = logger;

  /// Newest-first list (visual order).
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  bool get isExecuting => _executing;
  DownloadTask? get activeTask =>
      _activeTaskId == null ? null : _byId(_activeTaskId!);

  DownloadTask? _byId(String id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Public lookup by stable id (used by the UI to localize validation errors).
  DownloadTask? taskById(String id) => _byId(id);

  bool canEdit(DownloadTask task) {
    switch (task.status) {
      case TaskStatus.pending:
      case TaskStatus.paused:
      case TaskStatus.failed:
      case TaskStatus.cancelled:
        return true;
      case TaskStatus.queued:
      case TaskStatus.downloading:
      case TaskStatus.merging:
      case TaskStatus.completed:
        return false;
    }
  }

  // ------------------------------------------------------------------ #
  // Persistence / restore
  // ------------------------------------------------------------------ #

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs?.getString(prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        _tasks.clear();
        for (final e in list) {
          final task = DownloadTask.fromJson(Map<String, dynamic>.from(e as Map));
          if (task.id.isEmpty) continue;
          // Conservative recovery: a task that was mid-flight when the process
          // died must never be silently marked completed/failed.
          if (task.status.isActive) {
            task.status = TaskStatus.paused;
            task.phase = null;
            task.progressKnown = false;
          }
          _tasks.add(task);
        }
        for (final t in _tasks) {
          if (t.sequence != null && t.sequence! >= _seqCounter) {
            _seqCounter = t.sequence! + 1;
          }
        }
      } catch (e) {
        _logger.e('[Queue] Failed to load persisted queue: $e');
      }
    }

    // Cross-check the native foreground service's authoritative active-task
    // state. If the service still owns an in-flight task, surface it as paused
    // so the user must explicitly Resume it.
    if (Platform.isAndroid) {
      try {
        final active = await _python.getActiveDownload();
        final phase = active?['phase']?.toString();
        if (active != null && (phase == 'downloading' || phase == 'merging')) {
          final url = active['url']?.toString();
          for (final t in _tasks) {
            if (t.url == url && t.status.isActive) {
              t.status = TaskStatus.paused;
              t.phase = null;
            }
          }
        }
      } catch (e) {
        _logger.w('[Queue] Active-task reconciliation failed: $e');
      }
    }
    notifyListeners();

    // Resume approved-but-not-yet-started tasks after recovery. A task that was
    // interrupted mid-download is left in `paused` and requires an explicit
    // Resume, but a `queued` task was never started, so continuing it prevents
    // the queue from becoming stuck after process/activity recreation.
    if (_tasks.any((t) => t.status == TaskStatus.queued)) {
      unawaited(_ensureRunning());
    }
  }

  List<Map<String, dynamic>> _serializeTasks() =>
      _tasks.map((t) => t.toJson()).toList();

  /// Persist the full queue to Dart storage AND (on Android) the native
  /// foreground-service snapshot. Used for structural changes (add/edit/
  /// approval/removal/terminal states), where a stable snapshot is required.
  void _persist() {
    if (_disposed) return;
    final data = jsonEncode(_serializeTasks());
    unawaited(_prefs?.setString(prefsKey, data));
    _persistSnapshot();
  }

  /// Persist only the native queue snapshot (structural changes only).
  void _persistSnapshot() {
    if (_disposed || !Platform.isAndroid) return;
    unawaited(_python.saveQueueSnapshot(_serializeTasks()));
  }

  /// Persist progress throttled (local storage only). Progress ticks are
  /// frequent and their exact value is not needed for recovery, so we avoid
  /// both a SharedPreferences write storm and flooding the native snapshot.
  void _persistProgress() {
    if (_disposed) return;
    final now = DateTime.now();
    if (_lastProgressPersist != null &&
        now.difference(_lastProgressPersist!) < const Duration(seconds: 1)) {
      return;
    }
    _lastProgressPersist = now;
    final data = jsonEncode(_serializeTasks());
    unawaited(_prefs?.setString(prefsKey, data));
  }

  // ------------------------------------------------------------------ #
  // Container creation / editing
  // ------------------------------------------------------------------ #

  DownloadTask addTask() {
    final id = 'task_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';
    final task = DownloadTask(id: id);
    _tasks.insert(0, task); // newest first
    _persist();
    notifyListeners();
    return task;
  }

  void _updateField(String id, void Function(DownloadTask) apply) {
    final task = _byId(id);
    if (task == null || !canEdit(task)) return;
    apply(task);
    task.error = null;
    task.errorCode = null;
    task.errorDetail = null;
    _persist();
    notifyListeners();
  }

  void updateUrl(String id, String value) => _updateField(id, (t) => t.url = value);
  void updatePlatform(String id, String value) =>
      _updateField(id, (t) => t.platform = value);
  void updateMode(String id, String value) => _updateField(id, (t) => t.mode = value);
  void updateFilename(String id, String value) =>
      _updateField(id, (t) => t.filename = value);

  // ------------------------------------------------------------------ #
  // Approval / execution
  // ------------------------------------------------------------------ #

  String? _validate(DownloadTask task) {
    final url = task.url.trim();
    if (!DownloadPaths.isUsableUrl(url)) {
      return QueueErrorCodes.invalidUrl;
    }
    if (!DownloadPaths.urlMatchesPlatform(url, task.platform)) {
      final detected = DownloadPaths.detectPlatform(url);
      if (detected != null && detected != task.platform) {
        task.errorDetail = detected;
        return QueueErrorCodes.crossPlatform;
      }
      return QueueErrorCodes.platformMismatch;
    }
    return null;
  }

  Future<String?> start(String id) async {
    final task = _byId(id);
    if (task == null) return 'Task not found';
    if (task.status.isActive) return null; // already running
    if (task.status == TaskStatus.completed) return null; // never restart

    final error = _validate(task);
    if (error != null) {
      task.error = null;
      task.errorCode = error;
      _persist();
      notifyListeners();
      return error;
    }

    task.error = null;
    task.errorCode = null;
    task.errorDetail = null;
    task.sequence ??= _seqCounter++;
    task.status = TaskStatus.queued;
    task.progress = 0;
    task.progressKnown = false;
    _persist();
    notifyListeners();

    await _ensureRunning();
    return null;
  }

  Future<String?> resume(String id) async {
    final task = _byId(id);
    if (task == null) return 'Task not found';
    if (task.status == TaskStatus.completed) return null;
    if (task.status.isActive) return null;

    final error = _validate(task);
    if (error != null) {
      task.error = null;
      task.errorCode = error;
      _persist();
      notifyListeners();
      return error;
    }

    task.error = null;
    task.errorCode = null;
    task.errorDetail = null;
    task.sequence ??= _seqCounter++;
    task.status = TaskStatus.queued;
    task.progress = 0;
    task.progressKnown = false;
    _persist();
    notifyListeners();

    await _ensureRunning();
    return null;
  }

  Future<bool> remove(String id) async {
    final task = _byId(id);
    if (task == null) return false;

    // If this is the active task, cancel the underlying download first so no
    // orphaned download keeps running after the user removes the entry.
    if (task.status.isActive && _activeTaskId == id) {
      await _python.cancelDownload();
      task.status = TaskStatus.cancelled;
    }

    _tasks.removeWhere((t) => t.id == id);
    if (_activeTaskId == id) _activeTaskId = null;
    _persist();
    notifyListeners();
    return true;
  }

  Future<void> cancel(String id) async {
    final task = _byId(id);
    if (task == null) return;
    if (task.status.isActive && _activeTaskId == id) {
      await _python.cancelDownload();
    }
    if (!task.status.isTerminal) {
      task.status = TaskStatus.cancelled;
      task.error = null;
      _persist();
      notifyListeners();
    }
  }

  // ------------------------------------------------------------------ #
  // Sequential execution engine
  // ------------------------------------------------------------------ #

  Future<void> _ensureRunning() async {
    if (_executing || _disposed) return;
    _executing = true;
    notifyListeners();
    try {
      await _runQueue();
    } finally {
      _executing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _runQueue() async {
    while (!_disposed) {
      final next = _nextEligible();
      if (next == null) break;
      _activeTaskId = next.id;
      await _executeTask(next);
      if (_activeTaskId == next.id) _activeTaskId = null;
    }
  }

  DownloadTask? _nextEligible() {
    DownloadTask? best;
    for (final t in _tasks) {
      if (t.status == TaskStatus.queued && t.sequence != null) {
        if (best == null || t.sequence! < best.sequence!) best = t;
      }
    }
    return best;
  }

  String? _resolveFilename(DownloadTask task, String outputDir) {
    if (task.filename.trim().isEmpty) return null;
    if (Platform.isAndroid) {
      final s = DownloadPaths.sanitizeFilename(task.filename);
      return s.isEmpty ? null : DownloadPaths.ensureExtension(s, task.mode);
    }
    return DownloadPaths.resolveOutputFilename(
      rawName: task.filename,
      mode: task.mode,
      fallbackName: 'download',
      directory: outputDir,
    );
  }

  Future<void> _executeTask(DownloadTask task) async {
    final outputDir = await _python.getPlatformDownloadDirectory(task.platform);
    final resolvedName = _resolveFilename(task, outputDir);

    final current = _byId(task.id);
    if (current == null) return;
    current.status = TaskStatus.downloading;
    current.phase = 'downloading';
    current.progress = 0;
    current.progressKnown = false;
    current.error = null;
    _persist();
    notifyListeners();

    try {
      await for (final progress in _python.downloadVideo(
        task.url,
        task.platform,
        DownloadPaths.bestQuality,
        outputDir,
        mode: task.mode,
        filename: resolvedName,
      )) {
        final live = _byId(task.id);
        if (live == null) {
          // Container was removed while downloading — never recreate it.
          await _python.cancelDownload();
          return;
        }
        live.progress = progress.percent;
        live.progressKnown = progress.totalBytes > 0 || progress.percent > 0;
        if (progress.phase == 'merging') {
          live.status = TaskStatus.merging;
          live.phase = 'merging';
        } else if (progress.phase == 'downloading') {
          live.status = TaskStatus.downloading;
          live.phase = 'downloading';
        }
        _persistProgress();
        notifyListeners();
      }

      final done = _byId(task.id);
      if (done == null) return;
      var outputFile = _python.lastDownloadResult?['file']?.toString();
      if (!Platform.isAndroid && resolvedName != null && outputFile != null) {
        outputFile = await _applyDesktopFilename(outputFile, outputDir, resolvedName);
      }
      done.status = TaskStatus.completed;
      done.progress = 100;
      done.progressKnown = true;
      done.phase = null;
      done.outputFile = outputFile;
      done.error = null;
      _persist();
      notifyListeners();
    } on DownloadCancelledException {
      final cancelled = _byId(task.id);
      if (cancelled == null) return;
      cancelled.status = TaskStatus.cancelled;
      cancelled.phase = null;
      cancelled.error = null;
      _persist();
      notifyListeners();
    } catch (e) {
      final failed = _byId(task.id);
      if (failed == null) return;
      failed.status = TaskStatus.failed;
      failed.phase = null;
      failed.error = e.toString().replaceAll('Exception: ', '');
      _persist();
      notifyListeners();
    }
  }

  /// On desktop, apply the resolved custom filename by renaming the produced
  /// file (yt-dlp names it from the media title). Falls back to a copy when a
  /// plain rename is unavailable (e.g. across filesystem boundaries).
  Future<String?> _applyDesktopFilename(
      String srcPath, String outputDir, String name) async {
    final src = File(srcPath);
    final targetPath = '$outputDir${Platform.pathSeparator}$name';
    if (src.path == targetPath) return src.path;
    try {
      if (!src.existsSync()) return src.path;
      final renamed = src.renameSync(targetPath);
      return renamed.path;
    } catch (_) {
      try {
        final copied = src.copySync(targetPath);
        src.deleteSync();
        return copied.path;
      } catch (_) {
        return src.path; // keep the original name on any failure
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
