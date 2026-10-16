/// Stable validation error codes used by the queue engine. The UI maps these
/// to localized messages, so the controller never hardcodes display text.
class QueueErrorCodes {
  static const String invalidUrl = 'invalidUrl';
  static const String crossPlatform = 'crossPlatform';
  static const String platformMismatch = 'platformMismatch';
}

/// Status lifecycle for a single download container in the Nazzelha Sawa queue.
enum TaskStatus {
  /// Waiting for the user to configure / approve it.
  pending,

  /// Approved by the user (Start) and waiting for its turn in the queue.
  queued,

  /// Data is actively downloading.
  downloading,

  /// FFmpeg is processing / merging / extracting the downloaded media.
  merging,

  /// Intentionally paused or interrupted and awaiting an explicit Resume.
  paused,

  /// Output file has been finalized and verified.
  completed,

  /// A genuine unrecoverable error occurred.
  failed,

  /// The user cancelled the task.
  cancelled;

  static TaskStatus fromName(String? name) {
    if (name == null) return TaskStatus.pending;
    for (final status in TaskStatus.values) {
      if (status.name == name) return status;
    }
    return TaskStatus.pending;
  }

  /// Whether the task currently occupies (or is eligible to occupy) the single
  /// queue execution slot.
  bool get isActive =>
      this == TaskStatus.downloading || this == TaskStatus.merging;

  /// Terminal states — the task will never transition out of these.
  bool get isTerminal =>
      this == TaskStatus.completed ||
      this == TaskStatus.failed ||
      this == TaskStatus.cancelled;

  /// Whether the user can edit this task's configuration.
  bool get isEditable => !isActive && this != TaskStatus.completed;
}

/// One immutable-by-identity download task in the queue.
///
/// The [id] is a stable unique identifier that never depends on the task's
/// list position, so removing/reordering containers cannot mis-route events.
class DownloadTask {
  final String id;
  String url;
  String platform;

  /// 'video' or 'audio'. Stored independently per container.
  String mode;

  /// User-supplied "Save as" filename (may be empty = use default title).
  String filename;

  TaskStatus status;
  int progress;
  bool progressKnown;
  String? phase;
  int? sequence;
  String? error;
  String? errorCode;
  String? errorDetail;
  String? outputFile;

  DownloadTask({
    required this.id,
    this.url = '',
    this.platform = 'youtube',
    this.mode = 'video',
    this.filename = '',
    this.status = TaskStatus.pending,
    this.progress = 0,
    this.progressKnown = false,
    this.phase,
    this.sequence,
    this.error,
    this.errorCode,
    this.errorDetail,
    this.outputFile,
  });

  DownloadTask copy() => DownloadTask(
        id: id,
        url: url,
        platform: platform,
        mode: mode,
        filename: filename,
        status: status,
        progress: progress,
        progressKnown: progressKnown,
        phase: phase,
        sequence: sequence,
        error: error,
        errorCode: errorCode,
        errorDetail: errorDetail,
        outputFile: outputFile,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'platform': platform,
        'mode': mode,
        'filename': filename,
        'status': status.name,
        'progress': progress,
        'progressKnown': progressKnown,
        'phase': phase,
        'sequence': sequence,
        'error': error,
        'errorCode': errorCode,
        'errorDetail': errorDetail,
        'outputFile': outputFile,
      };

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
        id: json['id']?.toString() ?? '',
        url: json['url']?.toString() ?? '',
        platform: json['platform']?.toString() ?? 'youtube',
        mode: json['mode']?.toString() ?? 'video',
        filename: json['filename']?.toString() ?? '',
        status: TaskStatus.fromName(json['status']?.toString()),
        progress: ((json['progress'] as num?) ?? 0).toInt(),
        progressKnown: json['progressKnown'] == true,
        phase: json['phase']?.toString(),
        sequence: json['sequence'] == null
            ? null
            : ((json['sequence'] as num?) ?? 0).toInt(),
        error: json['error']?.toString(),
        errorCode: json['errorCode']?.toString(),
        errorDetail: json['errorDetail']?.toString(),
        outputFile: json['outputFile']?.toString(),
      );
}
