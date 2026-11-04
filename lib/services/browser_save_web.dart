import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:web/web.dart' as web;

const _maxFile = 96 * 1024 * 1024;
const _maxCache = 256 * 1024 * 1024;
final _files = <String, _BrowserFile>{};

class _BrowserFile {
  final web.Blob blob;
  final String filename;
  final expires = DateTime.now().add(const Duration(hours: 1));
  _BrowserFile(this.blob, this.filename);
}

void _cleanup() {
  for (final uri in _files.keys.toList()) {
    if (_files[uri]!.expires.isBefore(DateTime.now())) {
      web.URL.revokeObjectURL(uri);
      _files.remove(uri);
    }
  }
}

bool hasBrowserFile(String value) {
  _cleanup();
  return _files.containsKey(value);
}

class BrowserFileTransfer {
  final String filename;
  final int size;
  final _chunks = <JSAny>[];
  int _received = 0;
  BrowserFileTransfer(this.filename, this.size) {
    if (size < 1 || size > _maxFile) {
      throw StateError(
          'The free web edition supports files up to 96 MB. Choose a lower quality or use the app.');
    }
  }
  void addChunk(Uint8List data) {
    _received += data.length;
    if (_received > size || _received > _maxFile) {
      throw StateError('Invalid media transfer size.');
    }
    _chunks.add(data.toJS);
  }

  String finish() {
    if (_received != size) {
      throw StateError('Connection to the download service was lost.');
    }
    final blob = web.Blob(
        _chunks.toJS, web.BlobPropertyBag(type: 'application/octet-stream'));
    _chunks.clear();
    _cleanup();
    while (_files.isNotEmpty &&
        _files.values.fold<int>(0, (sum, file) => sum + file.blob.size) + size >
            _maxCache) {
      final oldest = _files.keys.first;
      web.URL.revokeObjectURL(oldest);
      _files.remove(oldest);
    }
    final uri = web.URL.createObjectURL(blob);
    _files[uri] = _BrowserFile(blob, filename);
    return uri;
  }

  void dispose() => _chunks.clear();
}

void saveBrowserFile(Uri uri) {
  final link = web.HTMLAnchorElement()
    ..href = uri.toString()
    ..download = _files[uri.toString()]?.filename ?? '';
  web.document.body!.append(link);
  link.click();
  link.remove();
}

Future<Uint8List> buildBrowserArchive(List<String> files, String folder) async {
  _cleanup();
  if (files.isEmpty || files.length > 200) {
    throw StateError('Choose between 1 and 200 prepared videos per ZIP.');
  }
  final selected = files.toSet().map((uri) => _files[uri]).toList();
  if (selected.any((file) => file == null)) {
    throw StateError('This temporary file expired. Prepare the video again.');
  }
  if (selected.fold<int>(0, (sum, file) => sum + file!.blob.size) >
      128 * 1024 * 1024) {
    throw StateError(
        'Please save these videos individually. The browser ZIP limit is 128 MB.');
  }
  final archive = Archive();
  final names = <String>{};
  for (var i = 0; i < selected.length; i++) {
    final file = selected[i]!;
    var name = file.filename;
    if (!names.add(name)) name = '${i + 1} - $name';
    final buffer = await file.blob.arrayBuffer().toDart;
    archive.addFile(ArchiveFile(
        '$folder/$name', file.blob.size, buffer.toDart.asUint8List())
      ..compression = CompressionType.none);
  }
  return Uint8List.fromList(ZipEncoder().encode(archive, level: 0));
}

Future<void> saveBrowserArchive(List<String> files, String folder) async {
  final zip = await buildBrowserArchive(files, folder);
  final blob =
      web.Blob([zip.toJS].toJS, web.BlobPropertyBag(type: 'application/zip'));
  final uri = web.URL.createObjectURL(blob);
  final link = web.HTMLAnchorElement()
    ..href = uri
    ..download = '$folder.zip';
  web.document.body!.append(link);
  link.click();
  link.remove();
  Timer(const Duration(minutes: 1), () => web.URL.revokeObjectURL(uri));
}
