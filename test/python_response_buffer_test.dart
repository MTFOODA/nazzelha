import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:nazzelha/services/python_service.dart';

void main() {
  test('cancelled worker releases its outstanding reader', () async {
    final buffer = PythonResponseBuffer();
    final pending = buffer.readNext(timeout: const Duration(minutes: 1));
    final assertion =
        expectLater(pending, throwsA(isA<DownloadCancelledException>()));
    buffer.close(DownloadCancelledException('cancelled'));
    await assertion;
    await expectLater(buffer.readNext(timeout: const Duration(seconds: 1)),
        throwsA(isA<DownloadCancelledException>()));
  });
  test('expired response waiter cannot consume the next response', () async {
    final buffer = PythonResponseBuffer();
    await expectLater(buffer.readNext(timeout: const Duration(milliseconds: 1)),
        throwsA(isA<TimeoutException>()));
    buffer.addResponse('{"success":true}');
    expect(await buffer.readNext(timeout: const Duration(seconds: 1)),
        '{"success":true}');
  });
}
