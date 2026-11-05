import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/app_release.dart';
import 'visit_session.dart';

class AppStatistics {
  final int visits;
  final int? windows;
  final int? android;
  final bool stale;
  const AppStatistics(
      {required this.visits, this.windows, this.android, this.stale = false});
  factory AppStatistics.fromJson(Map<String, dynamic> json) {
    final downloads = json['downloads'] as Map<String, dynamic>?;
    return AppStatistics(
        visits: json['visits'] as int,
        windows: downloads?['windows'] as int?,
        android: downloads?['android'] as int?,
        stale: downloads?['stale'] == true);
  }
}

class AppStatisticsService {
  final http.Client _client;
  Future<void>? _visit;
  AppStatisticsService({http.Client? client})
      : _client = client ?? http.Client();
  Uri _url(String path) => AppRelease.website.resolve('/api/stats$path');
  Future<AppStatistics> load() async {
    if (_visit != null) await _visit;
    final response =
        await _client.get(_url('')).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw Exception('Statistics unavailable');
    return AppStatistics.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> recordWebsiteVisit() => _visit ??= _recordWebsiteVisit();
  Future<void> _recordWebsiteVisit() async {
    final session = visitSession();
    if (session == null) {
      return; // Installed apps do not count as website visits.
    }
    try {
      await _client
          .post(_url('/visit'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'session': session}))
          .timeout(const Duration(seconds: 10));
    } catch (_) {} // Analytics never blocks startup or downloading.
  }

  void dispose() => _client.close();
}
