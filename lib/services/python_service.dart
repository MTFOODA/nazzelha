import 'runtime_platform.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

import '../models/download_progress.dart';
import 'download_paths.dart';
import 'browser_save.dart';
import 'remote_file_transfer.dart';

/// Raised when a download was explicitly cancelled by the user. Keeping this
/// distinct from a generic failure lets the UI show "cancelled" instead of
/// "failed".
class DownloadCancelledException implements Exception {
  final String message;
  DownloadCancelledException(this.message);
  @override
  String toString() => message;
}

class WebFileExpiredException implements Exception {
  @override
  String toString() => 'This temporary file expired. Prepare the video again.';
}

class PythonResponseBuffer {
  Object? _closedError;
  final Queue<String> _pendingResponses = Queue<String>();
  final List<Completer<String>> _waiters = <Completer<String>>[];

  void addResponse(String response) {
    if (_closedError != null) return;
    if (_waiters.isNotEmpty) {
      final completer = _waiters.removeAt(0);
      if (!completer.isCompleted) {
        completer.complete(response);
      }
      return;
    }

    _pendingResponses.addLast(response);
  }

  Future<String> readNext({required Duration timeout}) {
    if (_closedError != null) return Future.error(_closedError!);
    if (_pendingResponses.isNotEmpty) {
      return Future.value(_pendingResponses.removeFirst());
    }

    final completer = Completer<String>();
    _waiters.add(completer);
    return completer.future.timeout(timeout).whenComplete(() {
      _waiters.remove(completer);
    });
  }

  void close(Object error) {
    _closedError = error;
    _pendingResponses.clear();
    for (final waiter in _waiters) {
      if (!waiter.isCompleted) waiter.completeError(error);
    }
    _waiters.clear();
  }
}

class PythonService {
  final Logger logger;
  Process? _pythonProcess;
  StreamSubscription<String>? _stdoutSubscription;
  PythonResponseBuffer? _responseBuffer;
  StreamSubscription<List<int>>? _stderrSubscription;
  Map<String, dynamic>? lastDownloadResult;
  bool _isInitialized = false;
  bool _useHttpBackend = false;
  bool _androidLocalBackend = false;
  bool _commandBusy = false;
  bool _downloadBusy = false;
  bool _nativePlaylistBusy = false;
  bool _browserTransfers = false;
  bool get browserTransfers => _browserTransfers;
  http.Client? _activeWebClient;
  bool _webCancelled = false;
  String? _downloadDirectory;
  Future<void>? _restartInProgress;
  String? _playlistFolder;
  bool get isBusy => _commandBusy || _downloadBusy || _nativePlaylistBusy;
  late String _httpBackendUrl;
  String? lastInitError;
  bool get isPublicWeb =>
      kIsWeb &&
      (const bool.fromEnvironment('NAZZELHA_PUBLIC_WEB') ||
          !{'localhost', '127.0.0.1', '::1'}.contains(Uri.base.host));
  static const MethodChannel _androidChannel = MethodChannel('nazzelha/python');

  /// REAL progress events pushed from the Android native side while a
  /// yt-dlp download is running (forwarded from Python progress hooks).
  final StreamController<Map<String, dynamic>> _androidEventController =
      StreamController<Map<String, dynamic>>.broadcast();

  PythonService({required this.logger});

  bool get isInitialized => _isInitialized;
  bool get usesHostedBackend => kIsWeb || RuntimePlatform.isIOS;

  Future<void> initialize() async {
    if (usesHostedBackend) {
      const configured = String.fromEnvironment('NAZZELHA_BACKEND');
      _httpBackendUrl = configured.isNotEmpty
          ? configured
          : RuntimePlatform.isIOS
              ? 'https://nazzelha.mohamed-fooda-mtf.workers.dev/api'
              : isPublicWeb
                  ? '/api'
                  : 'http://127.0.0.1:8000';
      _useHttpBackend = true;
      try {
        final response = await http
            .get(Uri.parse('$_httpBackendUrl/health'))
            .timeout(const Duration(seconds: 5));
        _isInitialized = response.statusCode == 200 &&
            jsonDecode(response.body)['ready'] == true;
        if (_isInitialized) {
          _browserTransfers =
              jsonDecode(response.body)['transfer'] == 'browser';
        }
      } catch (_) {
        _isInitialized = false;
      }
      lastInitError = _isInitialized
          ? null
          : (isPublicWeb || RuntimePlatform.isIOS)
              ? 'The free download service is waking up. Please try again shortly.'
              : 'Start the local backend: python python_backend/web_bridge.py, then reload this page.';
      return;
    }
    logger.i('[PythonService] Initialization started');
    logger.i('[PythonService] Platform: ${Platform.operatingSystem}');

    try {
      if (RuntimePlatform.isAndroid) {
        _useHttpBackend = false;
        _androidLocalBackend = false;
        _responseBuffer = PythonResponseBuffer();
        _isInitialized = false;

        // Initialize the Android-native Python backend via MethodChannel
        try {
          // Listen for REAL progress events pushed from the native side
          // while a download is running.
          _androidChannel.setMethodCallHandler((call) async {
            final args = call.arguments;
            if (args is Map) {
              final event = Map<String, dynamic>.from(args);
              if (call.method == 'onDownloadProgress') {
                event['_type'] = 'progress';
                _androidEventController.add(event);
              } else if (call.method == 'onDownloadResult') {
                event['_type'] = 'result';
                _androidEventController.add(event);
              }
            }
          });

          final response = await _androidChannel
              .invokeMethod<Map<dynamic, dynamic>>('initialize');
          if (response != null && response['ready'] == true) {
            _isInitialized = true;
            _androidLocalBackend = true;
            logger.i(
                '[PythonService] Android Python backend initialized successfully');
          } else {
            throw StateError(
                'Android Python backend did not report ready state. Response: $response');
          }
        } on PlatformException catch (e) {
          lastInitError =
              'Android Python backend initialization failed: ${e.message}';
          logger.e('[PythonService] $lastInitError');
          _isInitialized = false;
          rethrow;
        }
        return;
      }

      await _startDesktopBackend();
    } catch (e, st) {
      lastInitError = e.toString();
      logger.e('[PythonService] Initialization failed: ${e.toString()}');
      logger.e('[PythonService] Stack trace: $st');
      _isInitialized = false;
      _androidLocalBackend = false;
      _useHttpBackend = false;
      if (!RuntimePlatform.isAndroid && !RuntimePlatform.isIOS) {
        rethrow;
      }
    }
  }

  /// Spawn the desktop Python backend, wire up stdout/stderr and wait for the
  /// ready handshake. Used both by [initialize] and after a stalled request.
  Future<void> _startDesktopBackend() async {
    final bundledEngine = File(
        '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}backend${Platform.pathSeparator}nazzelha-engine.exe');
    final packaged = RuntimePlatform.isWindows && bundledEngine.existsSync();
    final pythonBackendPath =
        packaged ? bundledEngine.parent.path : _getPythonBackendPath();
    logger.i('[PythonService] Backend path: $pythonBackendPath');

    final backendDir = Directory(pythonBackendPath);
    if (!backendDir.existsSync()) {
      throw StateError(
          'Python backend directory not found at: $pythonBackendPath. Ensure a "python_backend" folder exists next to the Flutter project and contains main.py');
    }

    final mainFile = File('$pythonBackendPath${Platform.pathSeparator}main.py');
    if (!packaged && !mainFile.existsSync()) {
      throw StateError(
          'main.py not found in python backend at: ${mainFile.path}');
    }

    final pythonExe =
        packaged ? bundledEngine.path : await _resolvePythonExecutable();
    if (pythonExe == null) {
      throw StateError(
        'No valid Python interpreter is available to run the Nazzelha backend. Install Python and ensure the project virtual environment or NAZZELHA_PYTHON is configured.',
      );
    }

    _pythonProcess = await Process.start(
      pythonExe,
      packaged ? [] : ['-u', '-X', 'utf8', 'main.py'],
      workingDirectory: pythonBackendPath,
      mode: ProcessStartMode.normal,
      environment: {'PYTHONUTF8': '1', 'PYTHONIOENCODING': 'utf-8'},
    );
    _pythonProcess!.stdin.encoding = utf8;

    logger.i(
        '[PythonService] Python process started with PID: ${_pythonProcess?.pid} (exe: $pythonExe)');

    _responseBuffer = PythonResponseBuffer();

    // stdout carries the JSON protocol; every response line is queued for
    // whoever is currently awaiting a reply.
    _stdoutSubscription = _pythonProcess!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      _responseBuffer?.addResponse(line);
    });

    // stderr MUST be drained even though it is not part of the JSON protocol.
    // yt-dlp writes verbose error/challenge output there; if nobody reads the
    // pipe, the OS buffer fills up and the Python process blocks mid-write,
    // which previously left extraction requests hanging forever.
    _stderrSubscription = _pythonProcess!.stderr.listen((chunk) {
      final text = utf8.decode(chunk, allowMalformed: true).trim();
      if (text.isNotEmpty) {
        logger.d('[PythonBackend][stderr] $text');
      }
    }, onDone: () {
      logger.w('[PythonService] Python stderr stream closed');
    });

    final readyLine =
        await _readNextResponse(timeout: const Duration(seconds: 20));
    final readyResponse = jsonDecode(readyLine);
    if (readyResponse['ready'] == true) {
      _isInitialized = true;
      _androidLocalBackend = false;
      _useHttpBackend = false;
      logger.i('[PythonService] Desktop backend ready');
    } else {
      throw StateError(
          'Python backend did not report ready state. Response: $readyResponse');
    }
  }

  /// Kill a stalled backend (including child processes such as Node.js used
  /// by yt-dlp challenge solvers) and start a fresh one so the app keeps
  /// working after a timeout instead of talking to a zombie process.
  Future<void> _restartDesktopBackend({Object? reason}) {
    if (_restartInProgress != null) return _restartInProgress!;
    final future = _restartDesktopBackendImpl(reason);
    _restartInProgress = future;
    return future.whenComplete(() => _restartInProgress = null);
  }

  Future<void> _restartDesktopBackendImpl(Object? reason) async {
    logger.w('[PythonService] Restarting Python backend after stalled request');
    _isInitialized = false;
    _responseBuffer?.close(reason ?? StateError('Backend restarted'));
    final staleProcess = _pythonProcess;
    _pythonProcess = null;
    _responseBuffer = null;
    await _stdoutSubscription?.cancel();
    _stdoutSubscription = null;
    await _stderrSubscription?.cancel();
    _stderrSubscription = null;

    if (staleProcess != null) {
      try {
        if (RuntimePlatform.isWindows) {
          // /T kills the whole tree (python.exe + node.exe children), /F forces.
          final result = await Process.run(
            'taskkill',
            ['/PID', '${staleProcess.pid}', '/T', '/F'],
          );
          logger.i('[PythonService] taskkill exitCode: ${result.exitCode}');
        } else {
          staleProcess.kill();
        }
      } catch (e) {
        logger.w('[PythonService] Failed to kill stalled backend: $e');
      }
    }

    await _startDesktopBackend();
    logger.i('[PythonService] Python backend restarted successfully');
  }

  Future<Map<String, dynamic>> sendCommand(
    Map<String, dynamic> command, {
    Duration? timeout,
  }) async {
    if (_restartInProgress != null) await _restartInProgress;
    if (usesHostedBackend && !_isInitialized) await _connectWebBackend();
    if (!_isInitialized) {
      final message = lastInitError ?? 'Python service is not initialized';
      throw StateError(message);
    }

    if (isBusy) throw StateError('Another operation is running. Please wait.');
    _commandBusy = true;
    try {
      if (_androidLocalBackend) {
        return await _handleAndroidLocalCommand(command)
            .timeout(timeout ?? const Duration(minutes: 10));
      }

      if (RuntimePlatform.isAndroid ||
          (RuntimePlatform.isIOS && !_useHttpBackend)) {
        throw StateError(lastInitError ??
            'Android does not have a real Python backend in this build.');
      }

      if (_useHttpBackend) {
        final uri = Uri.parse('$_httpBackendUrl/command');
        final resp = await http
            .post(uri,
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(command))
            .timeout(timeout ?? const Duration(minutes: 10));
        if (resp.statusCode != 200) {
          throw Exception(_httpError(resp.statusCode, resp.body));
        }
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }

      if (_pythonProcess == null) {
        throw StateError('Python process is not initialized');
      }

      final commandJson = jsonEncode(command);
      _pythonProcess!.stdin.writeln(commandJson);
      await _pythonProcess!.stdin.flush();

      // Session imports contain credentials; command bodies never belong in logs.
      logger.d('Sent command: ${command['action']}');

      final responseLine = await _readNextResponse(
        timeout: timeout ?? const Duration(minutes: 10),
      );

      logger.d('Received response: $responseLine');

      return jsonDecode(responseLine) as Map<String, dynamic>;
    } catch (e, st) {
      logger.e('[PythonService] Error sending command: ${e.toString()}');
      logger.e('[PythonService] Stack trace: $st');
      if (e is TimeoutException &&
          !kIsWeb &&
          !RuntimePlatform.isAndroid &&
          !RuntimePlatform.isIOS) {
        await _restartDesktopBackend();
      }
      rethrow;
    } finally {
      _commandBusy = false;
    }
  }

  Future<List<int>> getAvailableQualities(
    String url,
    String platform,
  ) async {
    logger.i(
        '[Submit] Extraction request sent (platform: $platform, action: get_qualities)');

    Map<String, dynamic> response;
    try {
      // Quality extraction is metadata-only; it must never wait as long as a
      // download. The backend caps its own TikTok cascade at 140s (including
      // one cool-off rescue), so this 170s timeout only ever fires on a
      // genuinely dead process - which we then kill and respawn.
      response = await sendCommand(
        {
          'action': 'get_qualities',
          'url': url,
          'platform': platform,
        },
        timeout: const Duration(seconds: 170),
      );
    } catch (e) {
      if (e is TimeoutException || e.toString().contains('TimeoutException')) {
        logger
            .e('[Submit] Extraction timed out after 170s; restarting backend');
        throw Exception(
            'Video extraction timed out. The platform may be blocking the request right now - please press SUBMIT again.');
      }
      rethrow;
    }

    logger.i(
        '[Submit] Extraction response received (success: ${response['success']})');

    if (response['success'] == true) {
      final qualities = List<int>.from(response['qualities'] as List);
      return qualities;
    } else {
      throw Exception(response['error'] ?? 'Unknown error occurred');
    }
  }

  static bool isProgressPayload(Map<String, dynamic> payload) {
    return payload['event'] == 'progress' || payload.containsKey('percent');
  }

  static bool isTerminalResponse(Map<String, dynamic> payload) {
    return payload.containsKey('success');
  }

  Stream<DownloadProgress> downloadVideo(
    String url,
    String platform,
    int quality,
    String outputPath, {
    String mode = 'video',
    bool resume = false,
    String? filename,
  }) async* {
    if (_restartInProgress != null) await _restartInProgress;
    if (isBusy) throw StateError('Another operation is running. Please wait.');
    _downloadBusy = true;
    _webCancelled = false;
    lastDownloadResult = null;
    try {
      if (usesHostedBackend && !_isInitialized) await _connectWebBackend();
      if (!_isInitialized) {
        throw StateError(lastInitError ?? 'Python service is not initialized');
      }

      if (usesHostedBackend) {
        final client = http.Client();
        _activeWebClient = client;
        RemoteFileTransfer? transfer;
        try {
          final request =
              http.Request('POST', Uri.parse('$_httpBackendUrl/download'))
                ..headers['Content-Type'] = 'application/json'
                ..body = jsonEncode({
                  'url': url,
                  'platform': platform,
                  'quality': quality,
                  'mode': mode,
                  'folder_name': _playlistFolder,
                  'filename': filename,
                });
          final response = await client.send(request);
          if (response.statusCode != 200) {
            final body = await response.stream.bytesToString();
            throw Exception(_httpError(response.statusCode, body));
          }
          var completed = false;
          await for (final line in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
            final payload = jsonDecode(line) as Map<String, dynamic>;
            if (payload['event'] == 'file_start') {
              transfer?.dispose();
              transfer = RemoteFileTransfer(payload['filename'].toString(),
                  (payload['size'] as num).toInt(),
                  directory: outputPath);
            } else if (payload['event'] == 'file_chunk') {
              if (transfer == null) throw StateError('Invalid media transfer.');
              transfer.addChunk(base64Decode(payload['data'] as String));
            } else if (isProgressPayload(payload)) {
              yield DownloadProgress.fromJson(payload);
            } else if (isTerminalResponse(payload)) {
              if (payload['cancelled'] == true) {
                throw DownloadCancelledException('Download cancelled');
              }
              if (payload['success'] != true) throw Exception(payload['error']);
              if (payload['transfer'] == 'browser') {
                if (transfer == null) {
                  throw StateError('Invalid media transfer.');
                }
                payload['file'] = transfer.finish();
              } else if (RuntimePlatform.isIOS) {
                throw StateError(
                    'The hosted service did not return a file transfer.');
              }
              lastDownloadResult = payload;
              completed = true;
              yield DownloadProgress(
                  percent: 100,
                  speed: 'Complete',
                  eta: '00:00',
                  totalBytes: 0,
                  downloadedBytes: 0);
            }
          }
          if (!completed) {
            throw Exception('Connection to the download backend was lost.');
          }
        } finally {
          transfer?.dispose();
          _activeWebClient = null;
          client.close();
        }
        return;
      }

      if (_androidLocalBackend) {
        // Legacy devices (Android 9 and below) need WRITE_EXTERNAL_STORAGE
        // granted before the native side can save into the public Downloads
        // folder. Android 10+ uses MediaStore and needs no permission.
        try {
          final granted = await _androidChannel
              .invokeMethod<bool>('ensure_storage_permission');
          if (granted != true) {
            throw Exception(
                'Storage permission is required to save videos to your Downloads.');
          }
        } on PlatformException catch (e) {
          logger.e(
              '[PythonService] ensure_storage_permission failed: ${e.message}');
          throw Exception(e.message ?? 'Failed to obtain storage permission');
        }

        // Subscribe to REAL progress AND terminal-result events forwarded by the
        // native foreground service. A terminal result is only reported when the
        // download engine confirms it; a lost callback or lifecycle pause never
        // becomes a failure.
        final progressController = StreamController<DownloadProgress>();
        late final StreamSubscription<Map<String, dynamic>> eventSub;
        eventSub = _androidEventController.stream.listen((event) {
          if (event['playlist_id'] != null ||
              (event['url'] != null && event['url'] != url)) {
            return;
          }
          if (event['_type'] == 'progress') {
            progressController.add(DownloadProgress.fromJson(event));
          } else if (event['_type'] == 'result') {
            final phase = event['phase']?.toString();
            if (event['success'] == true) {
              lastDownloadResult = Map<String, dynamic>.from(event);
              progressController.add(DownloadProgress(
                percent: 100,
                speed: 'Complete',
                eta: '00:00',
                totalBytes: ((event['size'] as num?) ?? 0).toInt(),
                downloadedBytes: ((event['size'] as num?) ?? 0).toInt(),
              ));
              progressController.close();
            } else if (phase == 'cancelled') {
              progressController.addError(DownloadCancelledException(
                  event['error']?.toString() ?? 'Download cancelled'));
              progressController.close();
            } else {
              progressController.addError(
                  Exception(event['error']?.toString() ?? 'Download failed'));
              progressController.close();
            }
          }
        });

        if (!resume) {
          try {
            await _androidChannel.invokeMethod<Map<dynamic, dynamic>>(
              'start_download',
              {
                'url': url,
                'platform': platform,
                'quality': quality,
                'output_path': outputPath,
                'mode': mode,
                'filename': filename ?? '',
              },
            );
          } catch (e) {
            progressController.addError(e);
            progressController.close();
          }
        }

        try {
          yield* progressController.stream;
        } finally {
          await eventSub.cancel();
        }
        return;
      }

      if (RuntimePlatform.isAndroid || RuntimePlatform.isIOS) {
        final response = await sendCommand({
          'action': 'download',
          'url': url,
          'platform': platform,
          'quality': quality,
          'output_path': outputPath,
          'mode': mode,
          'filename': filename ?? '',
        });

        if (response['success'] == true) {
          final filePath = (response['file'] ?? '').toString();
          final file = filePath.isNotEmpty ? File(filePath) : null;
          if (file == null || !file.existsSync() || await file.length() <= 0) {
            throw StateError(
                'Download reported success but the file was not created or is empty: $filePath');
          }

          lastDownloadResult = {
            ...response,
            'file': file.path,
            'filename': response['filename'] ?? file.uri.pathSegments.last,
          };

          yield DownloadProgress(
            percent: 100,
            speed: 'Complete',
            eta: '00:00',
            totalBytes: await file.length(),
            downloadedBytes: await file.length(),
          );
          return;
        }

        throw Exception(response['error'] ?? 'Download failed');
      }

      if (_useHttpBackend) {
        final response = await sendCommand({
          'action': 'download',
          'url': url,
          'platform': platform,
          'quality': quality,
          'output_path': outputPath,
          'mode': mode,
          'filename': filename ?? '',
        });

        if (response['success'] == true) {
          final filePath = (response['file'] ?? '').toString();
          final file = filePath.isNotEmpty ? File(filePath) : null;
          if (file == null || !file.existsSync() || await file.length() <= 0) {
            throw StateError(
                'Download reported success but the file was not created or is empty: $filePath');
          }

          lastDownloadResult = {
            ...response,
            'file': file.path,
            'filename': response['filename'] ?? file.uri.pathSegments.last,
          };

          yield DownloadProgress(
            percent: 100,
            speed: 'Complete',
            eta: '00:00',
            totalBytes: await file.length(),
            downloadedBytes: await file.length(),
          );
          return;
        }

        throw Exception(response['error'] ?? 'Download failed');
      }

      if (_pythonProcess == null) {
        throw StateError('Python process is not initialized');
      }

      final commandJson = jsonEncode({
        'action': 'download',
        'url': url,
        'platform': platform,
        'quality': quality,
        'output_path': outputPath,
        'mode': mode,
        'filename': filename ?? '',
      });

      _pythonProcess!.stdin.writeln(commandJson);
      await _pythonProcess!.stdin.flush();

      logger.d('Sent download command: $commandJson');

      final downloadBuffer = _responseBuffer!;
      while (true) {
        final line = await _readNextResponse(
            timeout: const Duration(minutes: 10), sourceBuffer: downloadBuffer);
        if (line.trim().isEmpty) {
          continue;
        }

        final payload = jsonDecode(line) as Map<String, dynamic>;

        if (payload['event'] == 'finished') {
          logger.i('Download finished event received: ${payload['filename']}');
          continue;
        }

        if (isProgressPayload(payload)) {
          yield DownloadProgress.fromJson(payload);
          continue;
        }

        if (!isTerminalResponse(payload)) {
          logger.w('Ignoring non-final stdout payload: $payload');
          continue;
        }

        lastDownloadResult = payload;

        if (payload['success'] == true) {
          final filePath = (payload['file'] ?? '').toString();
          if (filePath.isEmpty) {
            throw StateError('Download succeeded but returned no file path.');
          }

          final file = File(filePath);
          if (!file.existsSync() || await file.length() <= 0) {
            throw StateError(
                'Download succeeded but the file was missing or empty: $filePath');
          }

          lastDownloadResult = {
            ...payload,
            'file': file.path,
            'filename': payload['filename'] ?? file.uri.pathSegments.last,
          };

          yield DownloadProgress(
            percent: 100,
            speed: 'Complete',
            eta: '00:00',
            totalBytes: await file.length(),
            downloadedBytes: await file.length(),
          );
          return;
        }

        throw Exception(payload['error'] ?? 'Download failed');
      }
    } catch (e, st) {
      if (usesHostedBackend && _webCancelled) {
        throw DownloadCancelledException('Download cancelled');
      }
      logger.e('Download error: ${e.toString()}');
      logger.e('Download stack trace: $st');
      rethrow;
    } finally {
      _downloadBusy = false;
    }
  }

  Future<String> getDownloadDirectory() async {
    if (RuntimePlatform.isIOS) {
      final docs = await getApplicationDocumentsDirectory();
      final directory = Directory('${docs.path}/Nazzelha');
      await directory.create(recursive: true);
      return _downloadDirectory = directory.path;
    }
    if (RuntimePlatform.isAndroid) {
      // Informational only: the native side persists finished downloads into
      // the public Downloads/Nazzelha location via MediaStore, using its own
      // always-writable staging directory for the actual yt-dlp output.
      // Never fail here if the public directory cannot be created directly.
      final downloadsDir = await getDownloadsDirectory();
      final baseDir = downloadsDir ?? Directory('/storage/emulated/0/Download');
      final targetDir =
          Directory('${baseDir.path}${Platform.pathSeparator}Nazzelha');
      try {
        if (!targetDir.existsSync()) {
          targetDir.createSync(recursive: true);
        }
      } catch (_) {
        // The native layer will create it through MediaStore instead.
      }
      return targetDir.path;
    }

    final response = await sendCommand({
      'action': 'get_download_dir',
    });

    if (response['success'] == true) {
      return _downloadDirectory = response['download_dir'] as String;
    } else {
      throw Exception(response['error'] ?? 'Unable to get download directory');
    }
  }

  Future<Map<String, dynamic>> getPlaylist(String url) async {
    final result = await sendCommand({'action': 'get_playlist', 'url': url},
        timeout: const Duration(minutes: 5));
    if (result['success'] != true) throw Exception(result['error']);
    return result;
  }

  Future<Map<String, dynamic>> repairPlaylistFolder(
          String folder, List<String> files) =>
      sendCommand({
        'action': 'repair_playlist_folder',
        'folder': folder,
        'files': files
      });

  Future<void> startNativePlaylist(Map<String, dynamic> job) async {
    final granted =
        await _androidChannel.invokeMethod<bool>('ensure_storage_permission');
    if (granted != true) throw Exception('Storage permission is required.');
    await _androidChannel
        .invokeMethod('start_playlist', {'job': jsonEncode(job)});
    _nativePlaylistBusy = true;
  }

  Future<Map<String, dynamic>?> getNativePlaylist() async {
    final result = await _androidChannel
        .invokeMapMethod<String, dynamic>('get_playlist_job');
    _nativePlaylistBusy = result?['status'] == 'running';
    return result == null ? null : Map<String, dynamic>.from(result);
  }

  Future<void> removeNativePlaylistEntry(String jobId, String key) async {
    await _androidChannel
        .invokeMethod('remove_playlist_entry', {'job_id': jobId, 'key': key});
  }

  Future<void> openDownloadLocation(
      {String? file,
      String? folder,
      String platform = 'youtube',
      List<String>? files}) async {
    if (isPublicWeb) {
      if (file?.startsWith('blob:') == true) {
        if (!hasBrowserFile(file!)) throw WebFileExpiredException();
        saveBrowserFile(Uri.parse(file));
        return;
      }
      if (file == null && _browserTransfers) {
        await saveBrowserArchive(
            files ?? [], DownloadPaths.sanitizeFilename(folder ?? 'Playlist'));
        return;
      }
      if (file != null) {
        final uri = _publicFileUri(file);
        // Check expiration before asking the browser to save the attachment.
        final response =
            await http.head(uri).timeout(const Duration(seconds: 30));
        if (response.statusCode == 404) throw WebFileExpiredException();
        if (response.statusCode != 200) {
          throw Exception(_httpError(response.statusCode, response.body));
        }
        saveBrowserFile(uri);
      } else {
        final response = await http
            .post(Uri.parse('$_httpBackendUrl/archive'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'folder': folder, 'files': files ?? []}))
            .timeout(const Duration(minutes: 3));
        if (response.statusCode != 200) {
          throw Exception(_httpError(response.statusCode, response.body));
        }
        final result = jsonDecode(response.body) as Map;
        saveBrowserFile(_publicFileUri(result['file'].toString()));
      }
      return;
    }
    final command = {'file': file, 'folder': folder, 'platform': platform};
    if (RuntimePlatform.isAndroid) {
      await _androidChannel.invokeMethod('open_download_location', command);
      return;
    }
    if (kIsWeb) {
      final response = await http.post(
          Uri.parse('$_httpBackendUrl/open-location'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(command));
      final data = jsonDecode(response.body) as Map;
      if (data['success'] != true) {
        throw Exception(data['error'] ?? 'Could not open file location.');
      }
      return;
    }
    final root = Directory(_downloadDirectory ?? await getDownloadDirectory());
    final rootPath = await root.resolveSymbolicLinks();
    String target;
    if (file != null) {
      if (!File(file).existsSync()) {
        throw Exception('The downloaded file could not be found.');
      }
      target = await File(file).resolveSymbolicLinks();
    } else {
      final safe =
          folder == null ? null : DownloadPaths.sanitizeFilename(folder);
      final directory = Directory(
          '$rootPath/${DownloadPaths.platformFolder(platform)}${safe == null ? '' : '/Playlists/$safe'}');
      if (!directory.existsSync()) {
        throw Exception('The download folder could not be found.');
      }
      target = await directory.resolveSymbolicLinks();
    }
    final prefix = '$rootPath${Platform.pathSeparator}';
    if (!(RuntimePlatform.isWindows
        ? target.toLowerCase().startsWith(prefix.toLowerCase())
        : target.startsWith(prefix))) {
      throw Exception('Invalid download location.');
    }
    if (RuntimePlatform.isWindows) {
      await Process.start(
          'explorer.exe', file == null ? [target] : ['/select,', target]);
    } else if (RuntimePlatform.isMacOS) {
      await Process.start('open', file == null ? [target] : ['-R', target]);
    } else if (RuntimePlatform.isIOS) {
      await const MethodChannel('nazzelha/ios_files')
          .invokeMethod('show_files', {'path': target});
    } else {
      await Process.start(
          'xdg-open', [file == null ? target : File(target).parent.path]);
    }
  }

  Uri _publicFileUri(String value) {
    final uri = Uri.base.resolve(value);
    if (uri.origin != Uri.base.origin ||
        !RegExp(r'^/api/files/[a-f0-9]{48}$').hasMatch(uri.path)) {
      throw Exception('Invalid download link. Please prepare the video again.');
    }
    return uri;
  }

  String _httpError(int status, String body) {
    try {
      final data = jsonDecode(body) as Map;
      final detail = data['detail'] ?? data['error'];
      if (detail is String) return detail;
    } catch (_) {}
    return status == 429
        ? 'The free service is busy. Please try again shortly.'
        : 'The download service is unavailable. Please try again shortly.';
  }

  Future<void> _connectWebBackend() async {
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    do {
      try {
        final response = await http
            .get(Uri.parse('$_httpBackendUrl/health'))
            .timeout(const Duration(seconds: 20));
        if (response.statusCode == 200 &&
            jsonDecode(response.body)['ready'] == true) {
          _isInitialized = true;
          _browserTransfers =
              jsonDecode(response.body)['transfer'] == 'browser';
          lastInitError = null;
          return;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(seconds: 3));
    } while (isPublicWeb && DateTime.now().isBefore(deadline));
    throw StateError(lastInitError ??
        'The download service is unavailable. Please try again shortly.');
  }

  Stream<DownloadProgress> downloadPlaylistEntry(
      String url, String folder) async* {
    final base = await getPlatformDownloadDirectory('youtube');
    final safe = DownloadPaths.sanitizeFilename(folder);
    if (safe.isEmpty) throw Exception('Please enter a folder name.');
    final output = kIsWeb
        ? '$base/Playlists/$safe'
        : '$base${Platform.pathSeparator}Playlists${Platform.pathSeparator}$safe';
    if (!kIsWeb) await Directory(output).create(recursive: true);
    _playlistFolder = safe;
    try {
      yield* downloadVideo(url, 'youtube', DownloadPaths.bestQuality, output);
    } finally {
      _playlistFolder = null;
    }
  }

  /// Resolve the per-platform destination folder `Nazzelha/<Platform>/` under
  /// the existing Nazzelha download root. On Android this path is informational
  /// (the native foreground service persists via MediaStore using the same
  /// platform folder); on desktop it is the real yt-dlp output directory.
  Future<String> getPlatformDownloadDirectory(String platform) async {
    final base = await getDownloadDirectory();
    final folder = DownloadPaths.platformFolder(platform);
    if (kIsWeb) return '$base/$folder';
    final dir = Directory('$base${Platform.pathSeparator}$folder');
    try {
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
    } catch (_) {
      // The native layer (Android) creates the folder via MediaStore instead.
    }
    return dir.path;
  }

  Future<void> dispose() async {
    try {
      if (_restartInProgress != null) await _restartInProgress;
      await _stdoutSubscription?.cancel();
      _stdoutSubscription = null;
      await _stderrSubscription?.cancel();
      _stderrSubscription = null;
      _responseBuffer = null;

      if (_pythonProcess != null) {
        _pythonProcess!.kill();
        await _pythonProcess!.exitCode;
        logger.i('[PythonService] Python process terminated');
      }
    } catch (e, st) {
      logger.e(
          '[PythonService] Error terminating Python process: ${e.toString()}');
      logger.e('[PythonService] Stack trace: $st');
    }
  }

  Future<Map<String, dynamic>> _handleAndroidLocalCommand(
      Map<String, dynamic> command) async {
    final action = command['action'];
    if (action == 'get_auth_status' || action == 'configure_auth') {
      final result = await _androidChannel.invokeMapMethod<String, dynamic>(
          action as String, command);
      return Map<String, dynamic>.from(
          result ?? {'success': false, 'error': 'No response'});
    }
    if (action == 'get_playlist') {
      final result = await _androidChannel.invokeMapMethod<String, dynamic>(
          'get_playlist', {'url': command['url']});
      return Map<String, dynamic>.from(
          result ?? {'success': false, 'error': 'No response'});
    }

    if (action == 'get_download_dir') {
      try {
        final result = await _androidChannel
            .invokeMethod<Map<dynamic, dynamic>>('get_download_dir');
        if (result != null) {
          return Map<String, dynamic>.from(result);
        }
      } on PlatformException catch (e) {
        logger
            .e('[PythonService] Android get_download_dir failed: ${e.message}');
        throw Exception(e.message ?? 'Failed to get download directory');
      }
      final dir = await _defaultDownloadDirectory();
      return {
        'success': true,
        'download_dir': dir.path,
      };
    }

    if (action == 'get_qualities') {
      final url = (command['url'] ?? '').toString();
      final platform = (command['platform'] ?? 'youtube').toString();
      try {
        final result =
            await _androidChannel.invokeMethod<Map<dynamic, dynamic>>(
          'get_qualities',
          {'url': url, 'platform': platform},
        );
        if (result != null) {
          return Map<String, dynamic>.from(result);
        }
      } on PlatformException catch (e) {
        logger.e('[PythonService] Android get_qualities failed: ${e.message}');
        throw Exception(e.message ?? 'Failed to get qualities');
      }
      return {
        'success': true,
        'qualities': _qualityListForUrl(url),
      };
    }

    if (action == 'download') {
      final url = (command['url'] ?? '').toString();
      final platform = (command['platform'] ?? 'youtube').toString();
      final quality = (command['quality'] ?? 720) as int;
      final outputPath = (command['output_path'] ?? '').toString();
      final mode = (command['mode'] ?? 'video').toString();

      if (url.isEmpty) {
        return {
          'success': false,
          'error': 'Android download requires a valid URL.',
        };
      }

      try {
        final result =
            await _androidChannel.invokeMethod<Map<dynamic, dynamic>>(
          'download',
          {
            'url': url,
            'platform': platform,
            'quality': quality,
            'output_path': outputPath,
            'mode': mode,
          },
        );
        if (result != null) {
          return Map<String, dynamic>.from(result);
        }
      } on PlatformException catch (e) {
        logger.e('[PythonService] Android download failed: ${e.message}');
        throw Exception(e.message ?? 'Download failed');
      }
      return {
        'success': false,
        'error': 'Android download failed.',
      };
    }

    return {
      'success': false,
      'error': 'Unsupported Android command: $action',
    };
  }

  /// The authoritative state of the active (or most recently finished) download
  /// owned by the native foreground service. Used to restore the UI after an
  /// activity recreation without starting a duplicate download.
  Future<Map<String, dynamic>?> getActiveDownload() async {
    if (!RuntimePlatform.isAndroid) return null;
    try {
      final result = await _androidChannel
          .invokeMethod<Map<dynamic, dynamic>>('get_active_download');
      if (result == null) return null;
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      logger.w('[PythonService] get_active_download failed: ${e.message}');
      return null;
    }
  }

  /// Ask the native foreground service to cancel the active download.
  Future<void> cancelDownload() async {
    if (usesHostedBackend && _downloadBusy && _browserTransfers) {
      _webCancelled = true;
      _activeWebClient?.close();
      return;
    }
    if (kIsWeb && _downloadBusy) {
      await http
          .post(Uri.parse('$_httpBackendUrl/cancel'),
              headers: {'Content-Type': 'application/json'}, body: '{}')
          .timeout(const Duration(seconds: 10));
      return;
    }
    if (!kIsWeb &&
        !RuntimePlatform.isAndroid &&
        !RuntimePlatform.isIOS &&
        _downloadBusy) {
      await _restartDesktopBackend(
          reason: DownloadCancelledException('Download cancelled'));
      return;
    }
    if (!RuntimePlatform.isAndroid) return;
    try {
      await _androidChannel.invokeMethod('cancel_download');
    } on PlatformException catch (e) {
      logger.w('[PythonService] cancel_download failed: ${e.message}');
    }
  }

  /// Persist the complete Nazzelha queue snapshot into the native
  /// foreground service's durable storage (Android only). This lets the queue
  /// survive process death and be restored without duplicating active tasks.
  Future<void> saveQueueSnapshot(List<Map<String, dynamic>> tasks) async {
    if (!RuntimePlatform.isAndroid) return;
    try {
      await _androidChannel.invokeMethod('save_queue', {
        'queue': jsonEncode(tasks),
      });
    } on PlatformException catch (e) {
      logger.w('[PythonService] save_queue failed: ${e.message}');
    }
  }

  /// Read the queue snapshot persisted by the native foreground service
  /// (Android only). Returns null when unavailable.
  Future<List<Map<String, dynamic>>?> getQueueSnapshot() async {
    if (!RuntimePlatform.isAndroid) return null;
    try {
      final result =
          await _androidChannel.invokeMethod<List<dynamic>>('get_queue');
      if (result == null) return null;
      return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on PlatformException catch (e) {
      logger.w('[PythonService] get_queue failed: ${e.message}');
      return null;
    }
  }

  /// Open a downloaded media item on Android. Supports content:// URIs
  /// returned by MediaStore persistence.
  Future<void> openMedia(String uriOrPath) async {
    if (RuntimePlatform.isAndroid && uriOrPath.startsWith('content://')) {
      await _androidChannel.invokeMethod('open_media', {'uri': uriOrPath});
      return;
    }
    throw UnsupportedError('openMedia is only for Android content URIs');
  }

  Future<Directory> _defaultDownloadDirectory() async {
    if (RuntimePlatform.isAndroid) {
      final downloads = await getDownloadsDirectory();
      final root = downloads ?? Directory('/storage/emulated/0/Download');
      final dir = Directory('${root.path}${Platform.pathSeparator}Nazzelha');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return dir;
    }

    final homeDir =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    final root = homeDir != null && homeDir.isNotEmpty
        ? Directory(homeDir)
        : Directory.systemTemp;
    final downloadsDir = Directory(
        '${root.path}${Platform.pathSeparator}Downloads${Platform.pathSeparator}Nazzelha');
    if (!downloadsDir.existsSync()) {
      downloadsDir.createSync(recursive: true);
    }
    return downloadsDir;
  }

  List<int> _qualityListForUrl(String url) {
    final value = url.toLowerCase();
    if (value.contains('youtube') || value.contains('youtu.be')) {
      return [360, 480, 720, 1080];
    }

    if (value.contains('facebook') || value.contains('fb.watch')) {
      return [360, 480, 720];
    }

    if (value.contains('instagram') || value.contains('instagr.am')) {
      return [360, 480, 720, 1080];
    }

    if (value.contains('tiktok') ||
        value.contains('vt.tiktok.com') ||
        value.contains('vm.tiktok.com')) {
      return [360, 480, 720, 1080];
    }

    return const [360];
  }

  Future<String> _readNextResponse(
      {required Duration timeout, PythonResponseBuffer? sourceBuffer}) async {
    final buffer = sourceBuffer ?? _responseBuffer;
    if (buffer == null) {
      throw StateError('Python stdout buffer is not initialized');
    }

    while (true) {
      final line = await buffer.readNext(timeout: timeout);
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        continue;
      }

      if (trimmed.startsWith('{')) {
        return line;
      }

      logger.w('Ignoring non-JSON stdout line: $trimmed');
    }
  }

  // Try to find a python executable on the current platform.
  // Returns the executable name/path or null when not available (e.g., Android/iOS or not installed).
  Future<String?> _resolvePythonExecutable() async {
    final env = Platform.environment;
    final envExe = env['NAZZELHA_PYTHON'] ?? env['PYTHON_EXECUTABLE'];
    if (envExe != null && envExe.isNotEmpty) {
      try {
        final res = await Process.run(envExe, ['--version']);
        if (res.exitCode == 0) {
          logger.i('Using Python executable from env: $envExe');
          return envExe;
        }
      } catch (e) {
        logger.w('Configured python executable failed: $envExe -> $e');
      }
    }

    final projectRoot = Directory.current.path;
    final venvCandidates = <String>[];
    if (RuntimePlatform.isWindows) {
      venvCandidates.addAll([
        '$projectRoot${Platform.pathSeparator}.venv${Platform.pathSeparator}Scripts${Platform.pathSeparator}python.exe',
        '$projectRoot${Platform.pathSeparator}venv${Platform.pathSeparator}Scripts${Platform.pathSeparator}python.exe',
      ]);
    } else {
      venvCandidates.addAll([
        '$projectRoot${Platform.pathSeparator}.venv${Platform.pathSeparator}bin${Platform.pathSeparator}python',
        '$projectRoot${Platform.pathSeparator}venv${Platform.pathSeparator}bin${Platform.pathSeparator}python',
      ]);
    }

    for (final cand in venvCandidates) {
      final file = File(cand);
      if (file.existsSync()) {
        try {
          final result = await Process.run(cand, ['--version']);
          if (result.exitCode == 0) {
            logger.i('Found project Python executable: $cand');
            return cand;
          }
        } catch (_) {
          // ignore and continue
        }
      }
    }

    final candidates = <String>[];
    if (RuntimePlatform.isWindows) {
      candidates.addAll(['py', 'python', 'python3']);
    } else {
      candidates.addAll(['python3', 'python']);
    }

    for (final cand in candidates) {
      try {
        final result = await Process.run(cand, ['--version']);
        if (result.exitCode == 0) {
          logger.i('Found python executable: $cand');
          return cand;
        }
      } catch (_) {
        // ignore and try next candidate
      }
    }

    return null;
  }

  String _getPythonBackendPath() {
    final fileCandidates = <String>[];

    if (!RuntimePlatform.isAndroid && !RuntimePlatform.isIOS) {
      final executablePath = Platform.resolvedExecutable;
      final executableFile = File(executablePath);
      final executableDir = executableFile.existsSync()
          ? executableFile.parent.path
          : Directory.current.path;

      fileCandidates.addAll([
        Directory.current.path,
        executableDir,
        Directory(executableDir).parent.path,
        '${Directory(executableDir).parent.path}${Platform.pathSeparator}nazzelha_flutter',
        '${Directory(executableDir).parent.path}${Platform.pathSeparator}..',
      ]);
    }

    for (final candidateRoot in fileCandidates) {
      final candidateDirs = <String>{
        candidateRoot,
        '$candidateRoot${Platform.pathSeparator}python_backend',
        '${Directory(candidateRoot).parent.path}${Platform.pathSeparator}python_backend',
        '${Directory(candidateRoot).parent.path}${Platform.pathSeparator}nazzelha_flutter${Platform.pathSeparator}python_backend',
      };

      for (final candidate in candidateDirs) {
        final dir = Directory(candidate);
        if (dir.existsSync()) {
          final mainFile = File('${dir.path}${Platform.pathSeparator}main.py');
          if (mainFile.existsSync()) {
            return dir.path;
          }
        }
      }
    }

    final fallback =
        '${Directory.current.path}${Platform.pathSeparator}python_backend';
    if (Directory(fallback).existsSync()) {
      return fallback;
    }

    return fallback;
  }
}
