import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import 'package:nazzelha/services/python_service.dart';
import 'package:nazzelha/services/playlist_controller.dart';

class FixturePythonService extends PythonService {
  FixturePythonService() : super(logger: Logger(level: Level.off));
  @override
  bool get isInitialized => true;
  @override
  Future<Map<String, dynamic>> sendCommand(Map<String, dynamic> command,
          {Duration? timeout}) async =>
      {'success': true, 'platforms': <String, dynamic>{}};
  @override
  Future<List<int>> getAvailableQualities(String url, String platform) async =>
      [360, 720, 1080];
}

Future<void> seedPlaylist(PlaylistController c) async {
  c.job = {
    'id': 'ui-preview',
    'url': 'https://youtube.com/playlist?list=PLPqyWmL4W9D0',
    'title': 'اناشيد عامة',
    'folder': 'اناشيد عامة',
    'status': 'ready',
    'unavailable': 0,
    'entries': [
      {
        'id': 'xMZn23sSusg',
        'index': 1,
        'title': 'ذكّرينا يا بقايا الأمس فينا',
        'status': 'completed',
        'progress': 100,
        'file':
            r'D:\Downloads\Nazzelha\YouTube\Playlists\اناشيد عامة\ذكّرينا.mp4'
      },
      {
        'id': 'E6PBAtSDrxk',
        'index': 2,
        'title': 'تبلغ بالقليل — أسامة الصافي',
        'status': 'pending',
        'progress': 0
      },
      {
        'id': '5-TupqrVCCo',
        'index': 3,
        'title': 'ناديت وقلبي منكسر',
        'status': 'pending',
        'progress': 0
      },
    ],
  };
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(PlaylistController.prefsKey, jsonEncode(c.job));
  await c.load();
}
