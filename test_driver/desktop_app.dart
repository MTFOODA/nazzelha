import 'package:flutter_driver/driver_extension.dart';
import 'package:nazzelha/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  enableFlutterDriverExtension();
  SharedPreferences.setMockInitialValues({});
  app.main();
}
