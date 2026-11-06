import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'download_paths.dart';
import 'python_service.dart';
import 'runtime_platform.dart';

class PlaylistController extends ChangeNotifier {
  static int _lastJobTimestamp = 0;
  static const prefsKey = 'youtube_playlist_job';
  static const historyKey = 'youtube_playlist_history';
  static const dismissedKey = 'youtube_playlist_dismissed';
  static const clearedSelectionKey = 'youtube_playlist_selection_cleared';
  final PythonService python;
  Map<String, dynamic>? job;
  final List<Map<String, dynamic>> _history = [];
  final Set<String> _dismissed = {};
  bool loading = false;
  String? error;
  bool _stop = false,
      _disposed = false,
      _polling = false,
      _editingNative = false,
      _selectionCleared = false;
  int _nativeEpoch = 0;
  Timer? _timer;
  SharedPreferences? _prefs;
  PlaylistController(this.python);

  static List<Map<String, dynamic>> visibleEntries(
          Map<String, dynamic> value) =>
      (value['entries'] as List? ?? [])
          .where((e) => e['removed'] != true)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  List<Map<String, dynamic>> get entries =>
      job == null ? [] : visibleEntries(job!);
  List<Map<String, dynamic>> get history =>
      List.unmodifiable(_history.reversed);
  bool get running => job?['status'] == 'running';
  bool get anyRunning => _history.any((j) => j['status'] == 'running');
  bool get canStart => !anyRunning && !loading && !python.isBusy;
  bool get canClearCurrent =>
      job != null && !running && !anyRunning && !loading && !_editingNative;
  int get completed => entries.where((e) => e['status'] == 'completed').length;
  bool get hasRemaining => entries
      .any((e) => e['status'] != 'completed' && e['unavailable'] != true);
  String get folder => job?['folder']?.toString() ?? '';
  bool get folderLocked =>
      running ||
      (job?['entries'] as List? ?? [])
          .any((e) => e['file'] != null || e['status'] == 'completed');
  static String entryKey(Map entry) =>
      entry['key']?.toString() ?? '${entry['index']}:${entry['id']}';

  static String _newJobId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    _lastJobTimestamp = now > _lastJobTimestamp ? now : _lastJobTimestamp + 1;
    return 'playlist_$_lastJobTimestamp';
  }

  void _normalize(Map<String, dynamic> value) {
    value.putIfAbsent('createdAt', () => DateTime.now().toIso8601String());
    final list = value['entries'] as List? ?? [];
    for (var i = 0; i < list.length; i++) {
      final e = list[i] as Map;
      e.putIfAbsent('key', () => '${e['index'] ?? i}:${e['id'] ?? i}');
    }
    value['unavailable'] = list
        .where((e) => e['removed'] != true && e['unavailable'] == true)
        .length;
  }

  void _remember(Map<String, dynamic> value) {
    if (_dismissed.contains(value['id'])) return;
    _normalize(value);
    final index = _history.indexWhere((j) => j['id'] == value['id']);
    if (index < 0) {
      _history.add(value);
    } else {
      _history[index] = value;
    }
  }

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _selectionCleared = _prefs?.getBool(clearedSelectionKey) ?? false;
    _dismissed.addAll(_prefs?.getStringList(dismissedKey) ?? []);
    try {
      for (final saved
          in jsonDecode(_prefs?.getString(historyKey) ?? '[]') as List) {
        _remember(Map<String, dynamic>.from(saved as Map));
      }
      final raw = _prefs?.getString(prefsKey);
      if (raw != null && !_selectionCleared) {
        final previous = Map<String, dynamic>.from(jsonDecode(raw));
        if (!_dismissed.contains(previous['id'])) {
          final existing = _history.where((j) => j['id'] == previous['id']);
          job = existing.isNotEmpty ? existing.first : previous;
          _remember(job!);
        }
      }
      if (!python.usesHostedBackend &&
          !RuntimePlatform.isAndroid &&
          python.isInitialized) {
        for (final saved in _history) {
          final files = visibleEntries(saved)
              .map((e) => e['file']?.toString() ?? '')
              .where((p) => p.isNotEmpty)
              .toList();
          if (files.isEmpty) continue;
          try {
            final result = await python.repairPlaylistFolder(
                saved['folder'].toString(), files);
            final moved = result['files'] as Map? ?? {};
            for (final entry in saved['entries'] as List) {
              if (moved[entry['file']] != null) {
                entry['file'] = moved[entry['file']];
              }
            }
          } catch (e) {
            error = _message(e);
          }
        }
      }
      if (RuntimePlatform.isAndroid) {
        await refreshNative();
        _timer =
            Timer.periodic(const Duration(seconds: 1), (_) => refreshNative());
      } else {
        for (final saved in _history) {
          if (saved['status'] == 'running') {
            saved['status'] = 'paused';
            for (final e in saved['entries'] as List) {
              if (e['status'] == 'downloading') e['status'] = 'paused';
            }
          }
        }
      }
      if (!_selectionCleared) job ??= _history.isEmpty ? null : _history.last;
    } catch (e) {
      error = _message(e);
    }
    _changed();
  }

  Future<void> refreshNative() async {
    if (_disposed ||
        _polling ||
        _editingNative ||
        !RuntimePlatform.isAndroid ||
        loading) {
      return;
    }
    _polling = true;
    final epoch = _nativeEpoch;
    try {
      final native = await python.getNativePlaylist();
      if (!_editingNative &&
          epoch == _nativeEpoch &&
          native != null &&
          !_dismissed.contains(native['id'])) {
        _remember(native);
        if (!_selectionCleared && (job == null || native['id'] == job!['id'])) {
          job = native;
        }
        _changed();
      }
    } catch (e) {
      error = _message(e);
    } finally {
      _polling = false;
    }
  }

  void select(String id) {
    final match = _history.where((j) => j['id'] == id);
    if (match.isEmpty) return;
    _selectionCleared = false;
    job = match.first;
    error = null;
    _changed();
  }

  Future<void> extract(String url) async {
    if (anyRunning || loading) return;
    if (!DownloadPaths.isYoutubePlaylist(url)) {
      error = 'Please enter a YouTube playlist URL containing list=.';
      _changed();
      return;
    }
    loading = true;
    error = null;
    _changed();
    try {
      final result = await python.getPlaylist(url.trim());
      _selectionCleared = false;
      job = {
        'id': _newJobId(),
        'url': url.trim(),
        'title': result['title'],
        'folder': DownloadPaths.sanitizeFilename(
            result['title']?.toString() ?? 'Playlist'),
        'status': 'ready',
        'unavailable': result['unavailable'] ?? 0,
        'entries': (result['entries'] as List)
            .map((entry) => {
                  ...Map<String, dynamic>.from(entry as Map),
                  'status':
                      entry['unavailable'] == true ? 'unavailable' : 'pending',
                  'progress': 0,
                })
            .toList(),
      };
    } catch (e) {
      error = _message(e);
    } finally {
      loading = false;
      _changed();
    }
  }

  void setFolder(String name) {
    if (job == null || folderLocked) return;
    job!['folder'] = name;
    _changed();
  }

  /// Clear only the editor selection. History, saved files and browser transfers stay available.
  bool clearCurrent() {
    if (!canClearCurrent) return false;
    _selectionCleared = true;
    _nativeEpoch++; // Ignore a poll started before the user cleared the page.
    job = null;
    error = null;
    _changed();
    return true;
  }

  Future<void> start() => _run();
  Future<void> resumeEntry(String key) => _run(onlyKey: key);

  void expireWebFile(String key) {
    if (!python.isPublicWeb || job == null) return;
    for (final entry in job!['entries'] as List) {
      if (entryKey(entry) == key && entry['status'] == 'completed') {
        entry['status'] = 'failed';
        entry['file'] = null;
        entry['error'] =
            'This temporary file expired. Prepare the video again.';
      }
    }
    _changed();
  }

  Future<void> _run({String? onlyKey}) async {
    if (job == null || anyRunning || loading) return;
    final current = job!;
    _normalize(current);
    final list = current['entries'] as List;
    if (onlyKey == null && !hasRemaining) return;
    if (onlyKey != null) {
      final selected =
          list.where((e) => e['key'] == onlyKey && e['removed'] != true);
      if (selected.isEmpty ||
          selected.first['status'] == 'completed' ||
          (selected.first['url']?.toString() ?? '').isEmpty) {
        return;
      }
      selected.first['unavailable'] = false;
    }
    final safe =
        DownloadPaths.sanitizeFilename(current['folder']?.toString() ?? '');
    if (safe.isEmpty) {
      error = 'Please enter a folder name.';
      _changed();
      return;
    }
    if (python.isBusy) {
      error = 'Another operation is running. Please wait.';
      _changed();
      return;
    }
    current['folder'] = safe;
    current.remove('error');
    current.remove('only_entry');
    if (onlyKey != null) current['only_entry'] = onlyKey;
    error = null;
    _stop = false;
    current['status'] = 'running';
    _changed();
    if (RuntimePlatform.isAndroid) {
      try {
        await python.startNativePlaylist(current);
      } catch (e) {
        current['status'] = 'paused';
        error = _message(e);
        _changed();
      }
      return;
    }
    for (final entry in list) {
      if (_stop || _disposed) break;
      if (entry['removed'] == true ||
          entry['status'] == 'completed' ||
          entry['unavailable'] == true ||
          (onlyKey != null && entry['key'] != onlyKey)) {
        continue;
      }
      entry['status'] = 'downloading';
      entry['error'] = null;
      _changed();
      try {
        await for (final progress
            in python.downloadPlaylistEntry(entry['url'], safe)) {
          if (entry['removed'] != true) {
            entry['progress'] = progress.percent.clamp(0, 99);
          }
          _changed(persist: false);
        }
        if (entry['removed'] != true) {
          entry['status'] = 'completed';
          entry['progress'] = 100;
          entry['file'] = python.lastDownloadResult?['file'];
        }
      } catch (e) {
        if (entry['removed'] != true) {
          entry['status'] =
              _stop || e is DownloadCancelledException ? 'paused' : 'failed';
          entry['error'] = e is DownloadCancelledException ? null : _message(e);
        }
      }
      _changed();
    }
    current.remove('only_entry');
    final remaining =
        visibleEntries(current).where((e) => e['status'] != 'completed');
    current['status'] = _stop || _disposed
        ? 'paused'
        : remaining.isEmpty
            ? 'completed'
            : 'partial';
    _changed();
  }

  Future<void> pause() async {
    if (!running) return;
    _stop = true;
    await python.cancelDownload();
    _changed();
  }

  Future<void> removeEntry(String key) async {
    if (job == null) return;
    final current = job!;
    final matches =
        (current['entries'] as List).where((e) => entryKey(e) == key);
    if (matches.isEmpty) return;
    final entry = matches.first;
    final wasDownloading = entry['status'] == 'downloading';
    _editingNative = true;
    _nativeEpoch++;
    try {
      if (RuntimePlatform.isAndroid) {
        await python.removeNativePlaylistEntry(current['id'].toString(), key);
      }
      entry['removed'] = true;
      entry['status'] = 'removed';
      if (!RuntimePlatform.isAndroid && wasDownloading) {
        await python.cancelDownload();
      }
      _changed();
    } catch (e) {
      error = _message(e);
      _changed();
    } finally {
      _editingNative = false;
    }
  }

  void removeHistory(String id) {
    if (_history.any((j) => j['id'] == id && j['status'] == 'running')) return;
    _dismissed.add(id);
    _history.removeWhere((j) => j['id'] == id);
    if (job?['id'] == id) job = _history.isEmpty ? null : _history.last;
    _changed();
  }

  String _message(Object e) => e
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('Bad state: ', '');
  void _changed({bool persist = true}) {
    if (_disposed) return;
    if (job != null) _remember(job!);
    if (persist) {
      unawaited(_prefs?.setBool(clearedSelectionKey, _selectionCleared));
      if (job != null) {
        unawaited(_prefs?.setString(prefsKey, jsonEncode(job)));
      } else {
        unawaited(_prefs?.remove(prefsKey));
      }
      unawaited(_prefs?.setString(historyKey, jsonEncode(_history)));
      unawaited(_prefs?.setStringList(dismissedKey, _dismissed.toList()));
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
