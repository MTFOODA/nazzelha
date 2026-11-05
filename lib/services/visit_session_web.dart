import 'dart:convert';
import 'dart:math';
import 'package:web/web.dart' as web;

String? _fallback;
String visitSession() {
  final now = DateTime.now().millisecondsSinceEpoch;
  try {
    final saved = web.window.localStorage.getItem('nazzelha-visit-session');
    if (saved != null) {
      final data = jsonDecode(saved) as Map<String, dynamic>;
      final age = now - (data['created'] as int);
      if (age >= 0 &&
          age < 30 * 60 * 1000 &&
          RegExp(r'^[a-f0-9]{64}$').hasMatch(data['id'] as String)) {
        return data['id'] as String;
      }
    }
  } catch (_) {}
  final random = Random.secure();
  final id = List.generate(
      32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  try {
    web.window.localStorage.setItem(
        'nazzelha-visit-session', jsonEncode({'id': id, 'created': now}));
    return id;
  } catch (_) {
    return _fallback ??= id;
  }
}
