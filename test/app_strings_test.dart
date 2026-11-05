import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nazzelha/l10n/app_strings.dart';

void main() {
  test('hosted YouTube challenge is distinct from publisher restrictions', () {
    const message =
        'YouTube is blocking requests from the hosted download service. Use the Android or Windows app for this link.';
    expect(const AppStrings(Locale('en')).errorMessage(message), message);
    final translated = const AppStrings(Locale('ar')).errorMessage(message);
    expect(translated, contains('خدمة التنزيل'));
    expect(translated, isNot(contains('ناشر')));
  });
  test('inaccessible video errors use the requested short publisher message',
      () {
    const ar = AppStrings(Locale('ar'));
    const en = AppStrings(Locale('en'));
    for (final error in [
      'Facebook did not return video data',
      'Please login',
      'Could not extract this media',
      'Private video is not available'
    ]) {
      expect(ar.errorMessage(error), 'الفيديو مغلق من ناشر الفيديو.');
      expect(
          en.errorMessage(error), 'This video is restricted by its publisher.');
    }
    expect(ar.errorMessage('Connection timed out'), contains('الاتصال'));
    expect(ar.navHome, 'نزلها');
    expect(en.appTitle, 'Nazzelha');
  });
}
