import 'dart:typed_data';

void saveBrowserFile(Uri uri) => throw UnsupportedError('Browser only');
bool hasBrowserFile(String value) => false;
Future<Uint8List> buildBrowserArchive(
        List<String> files, String folder) async =>
    throw UnsupportedError('Browser only');
Future<void> saveBrowserArchive(List<String> files, String folder) async =>
    throw UnsupportedError('Browser only');

class BrowserFileTransfer {
  BrowserFileTransfer(String filename, int size);
  void addChunk(Uint8List data) => throw UnsupportedError('Browser only');
  String finish() => throw UnsupportedError('Browser only');
  void dispose() {}
}
