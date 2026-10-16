class DownloadProgress {
  final int percent;
  final String speed;
  final String eta;
  final int totalBytes;
  final int downloadedBytes;

  /// Engine phase: 'downloading', 'merging' (FFmpeg post-processing), or null
  /// when unknown. Derived from the backend's `status` field.
  final String? phase;

  DownloadProgress({
    required this.percent,
    required this.speed,
    required this.eta,
    required this.totalBytes,
    required this.downloadedBytes,
    this.phase,
  });

  String get downloadedMB => (downloadedBytes / (1024 * 1024)).toStringAsFixed(2);
  String get totalMB => (totalBytes / (1024 * 1024)).toStringAsFixed(2);

  factory DownloadProgress.fromJson(Map<String, dynamic> json) {
    final status = json['status']?.toString();
    final phase = status == 'finished'
        ? 'merging'
        : (status == 'downloading' ? 'downloading' : json['phase']?.toString());

    return DownloadProgress(
      // yt-dlp reports fractional percentages; keep them as whole numbers
      // for display while tolerating both int and num JSON types.
      percent: ((json['percent'] as num?) ?? 0).toInt(),
      speed: (json['speed'] ?? 'N/A').toString(),
      eta: (json['eta'] ?? 'N/A').toString(),
      totalBytes: ((json['total_bytes'] as num?) ?? 0).toInt(),
      downloadedBytes: ((json['downloaded_bytes'] as num?) ?? 0).toInt(),
      phase: phase,
    );
  }
}
