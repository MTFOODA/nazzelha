import 'dart:js_interop';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:nazzelha/services/browser_save.dart';
import 'package:web/web.dart' as web;

Future<void> main() async {
  var result = 'FAIL';
  try {
    final bytes =
        Uint8List.fromList(List.generate(1024 * 1024 + 7, (i) => i % 251));
    final transfer = BrowserFileTransfer('فيديو.mp4', bytes.length);
    transfer.addChunk(bytes.sublist(0, 12345));
    transfer.addChunk(bytes.sublist(12345));
    final uri = transfer.finish();
    transfer.dispose();
    if (!hasBrowserFile(uri)) throw StateError('Missing finished transfer');
    final response = await web.window.fetch(uri.toJS).toDart;
    final buffer = await response.arrayBuffer().toDart;
    final received = buffer.toDart.asUint8List();
    if (received.length != bytes.length) throw StateError('Invalid length');
    for (var i = 0; i < bytes.length; i++) {
      if (received[i] != bytes[i]) throw StateError('Corrupt byte at $i');
    }
    final zip = await buildBrowserArchive([uri], 'اناشيد عامة');
    final archive = ZipDecoder().decodeBytes(zip);
    if (archive.files.single.name != 'اناشيد عامة/فيديو.mp4') {
      throw StateError('Corrupt Unicode ZIP folder');
    }
    final extracted = archive.files.single.content;
    for (var i = 0; i < bytes.length; i++) {
      if (extracted[i] != bytes[i]) throw StateError('Corrupt ZIP byte at $i');
    }
    var rejected = false;
    try {
      BrowserFileTransfer('large.mp4', 97 * 1024 * 1024);
    } catch (_) {
      rejected = true;
    }
    if (!rejected) throw StateError('Oversize transfer accepted');
    rejected = false;
    final incomplete = BrowserFileTransfer('incomplete.mp4', 10)
      ..addChunk(Uint8List(9));
    try {
      incomplete.finish();
    } catch (_) {
      rejected = true;
    }
    if (!rejected) throw StateError('Incomplete transfer accepted');
    result =
        'PASS: byte reconstruction, Arabic ZIP folder, ZIP contents, size and completeness validation';
  } catch (error, stack) {
    result = 'FAIL: $error\n$stack';
  }
  web.document.title = result.startsWith('PASS') ? 'PASS' : 'FAIL';
  web.document.body!.textContent = result;
  await web.window
      .fetch('/result'.toJS, web.RequestInit(method: 'POST', body: result.toJS))
      .toDart;
}
