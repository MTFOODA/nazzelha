import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'download_paths.dart';

/// Writes hosted transfers to app-owned storage; a partial file is never final.
class RemoteFileTransfer {
  final int size;
  late final File _partial;
  late final File _target;
  RandomAccessFile? _writer;
  int _received = 0;
  bool _finished = false;

  RemoteFileTransfer(String filename, this.size, {required String directory}) {
    if (size < 1 || size > 96 * 1024 * 1024) {
      throw StateError(
          'The free web edition supports files up to 96 MB. Choose a lower quality or use the app.');
    }
    var safe = DownloadPaths.sanitizeFilename(filename);
    if (safe.isEmpty) throw StateError('Invalid media filename.');
    final dot = safe.lastIndexOf('.');
    final candidate = dot > 0 ? safe.substring(dot) : '';
    final extension =
        RegExp(r'^\.[a-zA-Z0-9]{1,10}$').hasMatch(candidate) ? candidate : '';
    var stem = dot > 0 ? safe.substring(0, dot) : safe;
    while (utf8.encode(stem).length > 180) {
      stem = String.fromCharCodes(stem.runes.take(stem.runes.length - 1));
    }
    safe = '$stem$extension';
    final folder = Directory(directory)..createSync(recursive: true);
    var target = File('${folder.path}${Platform.pathSeparator}$safe');
    var count = 1;
    while (target.existsSync()) {
      target = File(
          '${folder.path}${Platform.pathSeparator}$stem (${count++})$extension');
    }
    _target = target;
    _partial =
        File('${target.path}.${DateTime.now().microsecondsSinceEpoch}.part');
    _writer = _partial.openSync(mode: FileMode.write);
  }

  void addChunk(Uint8List bytes) {
    if (_writer == null || _received + bytes.length > size) {
      throw StateError('Invalid media transfer size.');
    }
    _writer!.writeFromSync(bytes);
    _received += bytes.length;
  }

  String finish() {
    if (_writer == null || _received != size) {
      throw StateError('Connection to the download service was lost.');
    }
    _writer!.flushSync();
    _writer!.closeSync();
    _writer = null;
    if (_target.existsSync()) {
      throw StateError('The destination file already exists.');
    }
    _partial.renameSync(_target.path);
    _finished = true;
    return _target.path;
  }

  void dispose() {
    _writer?.closeSync();
    _writer = null;
    if (!_finished && _partial.existsSync()) _partial.deleteSync();
  }
}
