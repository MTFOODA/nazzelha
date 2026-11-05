import 'dart:typed_data';
import 'browser_save.dart';

class RemoteFileTransfer {
  final BrowserFileTransfer _transfer;
  RemoteFileTransfer(String filename, int size, {required String directory})
      : _transfer = BrowserFileTransfer(filename, size);
  void addChunk(Uint8List bytes) => _transfer.addChunk(bytes);
  String finish() => _transfer.finish();
  void dispose() => _transfer.dispose();
}
