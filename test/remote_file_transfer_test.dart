import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nazzelha/services/remote_file_transfer_io.dart';

void main() {
  late Directory folder;
  setUp(
      () => folder = Directory.systemTemp.createTempSync('nazzelha-transfer-'));
  tearDown(() => folder.deleteSync(recursive: true));

  test('writes exact bytes to a Unicode path and preserves existing files', () {
    File('${folder.path}/فيديو.mp4').writeAsBytesSync([9]);
    final transfer = RemoteFileTransfer('فيديو.mp4', 4, directory: folder.path);
    transfer.addChunk(Uint8List.fromList([1, 2]));
    transfer.addChunk(Uint8List.fromList([3, 4]));
    final path = transfer.finish();
    transfer.dispose();
    expect(File(path).readAsBytesSync(), [1, 2, 3, 4]);
    expect(File('${folder.path}/فيديو.mp4').readAsBytesSync(), [9]);
    expect(folder.listSync().where((f) => f.path.endsWith('.part')), isEmpty);
  });

  test('incomplete and oversized transfers do not become saved media', () {
    final transfer =
        RemoteFileTransfer('../../incomplete.mp4', 3, directory: folder.path);
    transfer.addChunk(Uint8List.fromList([1, 2]));
    expect(transfer.finish, throwsStateError);
    transfer.dispose();
    expect(folder.listSync(), isEmpty);
    expect(
        () => RemoteFileTransfer('large.mp4', 97 * 1024 * 1024,
            directory: folder.path),
        throwsStateError);
    final overflow =
        RemoteFileTransfer('overflow.mp4', 1, directory: folder.path);
    expect(() => overflow.addChunk(Uint8List(2)), throwsStateError);
    overflow.dispose();
    expect(folder.listSync(), isEmpty);
  });
}
