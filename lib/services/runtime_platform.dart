import 'dart:io';
import 'package:flutter/foundation.dart';

/// dart:io's Platform getters throw in a browser, so always guard them here.
class RuntimePlatform {
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isIOS => !kIsWeb && Platform.isIOS;
  static bool get isWindows => !kIsWeb && Platform.isWindows;
  static bool get isLinux => !kIsWeb && Platform.isLinux;
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;
}
