import 'dart:io';

/// Single shared source of truth for:
///  * the four supported platforms,
///  * URL validation against those platforms,
///  * the per-platform download subfolder under the existing Nazzelha root,
///  * output-filename sanitization / extension / traversal protection.
///
/// Both the main downloader and Nazzelha Sawa resolve their destination folder
/// through this class so every download entry point produces the same
/// `Nazzelha/<Platform>/<file>` layout.
class DownloadPaths {
  /// The four platforms supported by the app (order matches the main page).
  static const List<String> supportedPlatforms = [
    'youtube',
    'facebook',
    'instagram',
    'tiktok',
  ];

  /// Human-readable, stable, sanitized folder name for each platform.
  static const Map<String, String> _platformFolders = {
    'youtube': 'YouTube',
    'facebook': 'Facebook',
    'instagram': 'Instagram',
    'tiktok': 'TikTok',
  };

  /// Sentinel quality used by Nazzelha Sawa to mean "best available quality".
  /// The existing yt-dlp format selector caps by `height<=quality`, so a very
  /// high cap lets `bestvideo+bestaudio/best` select the best available stream
  /// without hardcoding any resolution/codec/format id.
  static const int bestQuality = 4320;

  DownloadPaths._();

  /// Folder name for a platform; falls back to a generic name when the
  /// platform is unknown (never derived from raw untrusted URL text).
  static String platformFolder(String platform) {
    return _platformFolders[platform.toLowerCase()] ?? 'Other';
  }

  /// Validate that [url] looks usable.
  static bool isUsableUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return false;
    final lower = trimmed.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  /// True when [url] clearly belongs to [platform].
  static bool urlMatchesPlatform(String url, String platform) {
    final lower = url.toLowerCase();
    switch (platform.toLowerCase()) {
      case 'youtube':
        return lower.contains('youtube.com') || lower.contains('youtu.be');
      case 'facebook':
        return lower.contains('facebook.com') || lower.contains('fb.watch');
      case 'instagram':
        return lower.contains('instagram.com') || lower.contains('instagr.am');
      case 'tiktok':
        return lower.contains('tiktok.com') ||
            lower.contains('vt.tiktok.com') ||
            lower.contains('vm.tiktok.com');
      default:
        return true;
    }
  }

  /// Best-effort detection of the platform a URL belongs to, or null when it
  /// cannot be determined. Used only to show a helpful cross-platform
  /// validation hint; never to silently re-route a download.
  static String? detectPlatform(String url) {
    for (final platform in supportedPlatforms) {
      if (urlMatchesPlatform(url, platform)) return platform;
    }
    return null;
  }

  /// Sanitize a user-supplied "Save as" value into a safe single file name.
  ///
  ///  * Strips path separators and control characters (never interprets the
  ///    field as a filesystem path, and prevents path traversal).
  ///  * Replaces filesystem-invalid characters.
  ///  * Guards Windows reserved names.
  ///  * Removes trailing dots/spaces and caps length.
  ///
  /// Returns an empty string when nothing usable remains, signalling the
  /// caller to fall back to the default title-derived naming.
  static String sanitizeFilename(String raw) {
    var name = raw.trim();

    // Strip everything before any path separator: the field is a *name*, not
    // a path. This is what guarantees path-traversal cannot escape the folder.
    name = name.replaceAll(RegExp(r'[\\/]+'), ' ').trim();

    // Replace control chars and characters invalid on common filesystems.
    name = name.replaceAll(RegExp(r'[\x00-\x1f\x7f<>:"|?*]'), ' ');

    // Collapse whitespace runs and trailing dots/spaces (Windows rejects them).
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    name = name.replaceAll(RegExp(r'[.\s]+$'), '');

    // Drop standalone "." and ".." segments: they are path-traversal artifacts
    // (the separators were already stripped above) and never a valid name part.
    final parts = name
        .split(' ')
        .where((p) => p != '.' && p != '..')
        .where((p) => p.isNotEmpty)
        .toList();
    name = parts.join(' ');

    if (name.isEmpty || name == '.' || name == '..') return '';

    // Windows reserved device names (with or without extension).
    final base = name.split('.').first.toUpperCase();
    const reserved = {
      'CON', 'PRN', 'AUX', 'NUL',
      'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
      'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
    };
    if (reserved.contains(base)) {
      name = '_$name';
    }

    // Cap the base name length before the extension to stay within FAT/sdcardfs
    // limits; keep the extension intact.
    final dot = name.lastIndexOf('.');
    if (dot > 0) {
      final stem = name.substring(0, dot);
      final ext = name.substring(dot);
      if (stem.length > 120) {
        name = '${stem.substring(0, 120)}$ext';
      }
    } else if (name.length > 120) {
      name = name.substring(0, 120);
    }

    return name;
  }

  /// Ensure the file name carries the extension for the selected [mode]
  /// ('video' -> .mp4, 'audio' -> .mp3). A wrong media extension is replaced;
  /// a missing one is appended; a correct one is left untouched.
  static String ensureExtension(String name, String mode) {
    final desired = mode == 'audio' ? '.mp3' : '.mp4';
    final lower = name.toLowerCase();
    if (lower.endsWith(desired)) return name;

    const mediaExts = [
      '.mp4', '.m4v', '.webm', '.mkv', '.mov',
      '.mp3', '.m4a', '.opus', '.wav', '.aac', '.flac',
    ];
    for (final ext in mediaExts) {
      if (lower.endsWith(ext)) {
        return '${name.substring(0, name.length - ext.length)}$desired';
      }
    }
    return '$name$desired';
  }

  /// Resolve the final output file name for a task. Empty [rawName] falls back
  /// to [fallbackName] (the title-derived name). Always sanitizes, ensures the
  /// correct extension, and resolves conflicts against [directory] (non-null
  /// on desktop where we can inspect the filesystem directly).
  static String resolveOutputFilename({
    required String rawName,
    required String mode,
    required String fallbackName,
    String? directory,
  }) {
    var candidate = rawName.trim().isEmpty
        ? _sanitizeName(fallbackName, mode)
        : sanitizeFilename(rawName);
    if (candidate.isEmpty) candidate = _sanitizeName(fallbackName, mode);
    candidate = ensureExtension(candidate, mode);

    if (directory == null || directory.isEmpty) return candidate;
    return _resolveConflict(directory, candidate);
  }

  /// Internal: sanitize an auto-generated (title-derived) name. Preserves the
  /// existing yt-dlp title handling while still producing a safe file name.
  static String _sanitizeName(String name, String mode) {
    var safe = sanitizeFilename(name);
    if (safe.isEmpty) safe = 'download';
    return ensureExtension(safe, mode);
  }

  /// Append " (1)", " (2)", ... until [candidate] does not collide inside
  /// [directory]. Android uses MediaStore for conflict handling, so this only
  /// runs on desktop where the filesystem is directly observable.
  static String _resolveConflict(String directory, String candidate) {
    final dir = Directory(directory);
    var current = candidate;
    var counter = 1;
    final dot = current.lastIndexOf('.');
    final stem = dot > 0 ? current.substring(0, dot) : current;
    final ext = dot > 0 ? current.substring(dot) : '';

    while (File('${dir.path}${Platform.pathSeparator}$current').existsSync()) {
      current = '$stem ($counter)$ext';
      counter++;
      if (counter > 10000) break; // safety valve
    }
    return current;
  }
}
