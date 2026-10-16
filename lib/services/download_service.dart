import 'dart:async';
import 'package:logger/logger.dart';
import '../models/download_progress.dart';
import 'python_service.dart';

class DownloadService {
  final PythonService pythonService;
  final Logger logger;

  StreamController<DownloadProgress>? _progressController;

  DownloadService({
    required this.pythonService,
    required this.logger,
  });

  Stream<DownloadProgress> downloadVideo({
    required String url,
    required String platform,
    required int quality,
    required String outputPath,
  }) async* {
    try {
      logger.i('Starting download: $url (quality: $quality, platform: $platform)');
      
      yield* pythonService.downloadVideo(url, platform, quality, outputPath);
      
      logger.i('Download completed successfully');
    } catch (e) {
      logger.e('Download failed: $e');
      rethrow;
    }
  }

  void dispose() {
    _progressController?.close();
  }
}
