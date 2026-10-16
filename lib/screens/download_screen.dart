import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:open_file/open_file.dart';
import 'package:provider/provider.dart';
import '../models/download_progress.dart';
import '../services/python_service.dart';
import '../theme/colors.dart';
import 'home_screen.dart';

class DownloadScreen extends StatefulWidget {
  final String url;
  final String platform;
  final int quality;
  final String mode;

  const DownloadScreen({
    super.key,
    required this.url,
    required this.platform,
    required this.quality,
    this.mode = 'video',
  });

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

enum DownloadFlowState { idle, downloading, success, failed, cancelled }

class _DownloadScreenState extends State<DownloadScreen>
    with WidgetsBindingObserver {
  late Future<void> _downloadFuture;
  String? _downloadError;
  String? _downloadedFile;
  DownloadProgress? _progress;
  DownloadFlowState _downloadState = DownloadFlowState.idle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startDownload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the user returns to the app the foreground service keeps the
    // download alive; we only need to reconnect if our stream was never
    // recreated. The existing stream survives a mere pause/resume, so this is
    // a no-op safety net — the real restore happens in _performDownload.
    if (state == AppLifecycleState.resumed &&
        _downloadState == DownloadFlowState.idle) {
      _startDownload();
    }
  }

  void _startDownload() {
    _downloadState = DownloadFlowState.downloading;
    _downloadError = null;
    _downloadedFile = null;
    _downloadFuture = _performDownload();
  }

  Future<void> _performDownload() async {
    try {
      final pythonService = Provider.of<PythonService>(context, listen: false);
      final downloadDir =
          await pythonService.getPlatformDownloadDirectory(widget.platform);

      // Restore an in-flight download instead of starting a duplicate when the
      // activity was recreated while the foreground service kept downloading.
      var resume = false;
      try {
        final active = await pythonService.getActiveDownload();
        if (active != null) {
          final phase = active['phase']?.toString();
          final activeUrl = active['url']?.toString();
          final activeMode = active['mode']?.toString();
          final resumed = phase == 'downloading' ||
              phase == 'merging' ||
              phase == 'queued' ||
              phase == 'preparing';
          if (resumed && activeUrl == widget.url && activeMode == widget.mode) {
            resume = true;
          }
        }
      } catch (_) {
        // Best-effort restore; fall through to a fresh start on any error.
      }

      await for (final progress in pythonService.downloadVideo(
        widget.url,
        widget.platform,
        widget.quality,
        downloadDir,
        mode: widget.mode,
        resume: resume,
      )) {
        if (!mounted) return;

        setState(() {
          _progress = progress;
          if (_progress!.percent >= 100) {
            _downloadedFile = pythonService.lastDownloadResult?['file']?.toString();
          }
        });
      }

      // On Android 10+ the persisted file is a MediaStore content:// URI that
      // dart:io cannot stat; the native side already validated existence and
      // size before returning success. Plain file paths are verified here.
      final savedTarget = _downloadedFile;
      if (savedTarget == null || savedTarget.isEmpty) {
        throw StateError('Video file not found.');
      }
      if (!savedTarget.startsWith('content://')) {
        final finalFile = File(savedTarget);
        if (!await finalFile.exists() || await finalFile.length() <= 0) {
          throw StateError('Video file not found.');
        }
      }

      if (!mounted) return;
      setState(() {
        _downloadState = DownloadFlowState.success;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (e is DownloadCancelledException) {
          _downloadState = DownloadFlowState.cancelled;
        } else {
          _downloadState = DownloadFlowState.failed;
        }
        _downloadError = e
            .toString()
            .replaceAll('Exception: ', '')
            .replaceAll('StateError: ', '');
      });
    }
  }

  Future<void> _cancelDownload() async {
    final pythonService = Provider.of<PythonService>(context, listen: false);
    await pythonService.cancelDownload();
  }

  Future<void> _openDownloadedFile(String filePath) async {
    try {
      // Android 10+ persisted files are MediaStore entries addressed by a
      // content:// URI and must be opened through the platform channel.
      if (filePath.startsWith('content://')) {
        final pythonService = Provider.of<PythonService>(context, listen: false);
        try {
          await pythonService.openMedia(filePath);
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _downloadError = 'Could not open video. Please open it from your Downloads folder.';
          });
        }
        return;
      }

      final file = File(filePath);
      if (!await file.exists()) {
        if (!mounted) return;
        setState(() {
          _downloadError = 'The downloaded file no longer exists at: $filePath';
        });
        return;
      }

      final result = await OpenFile.open(file.path);
      if (result.type != ResultType.done) {
        if (!mounted) return;
        setState(() {
          _downloadError = 'Video file not found.';
        });
        return;
      }

      if (result.message.isNotEmpty && result.type == ResultType.error) {
        if (!mounted) return;
        setState(() {
          _downloadError = result.message;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadError = 'Could not open file: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: _downloadedFile != null || _downloadError != null,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Downloading...',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
          centerTitle: true,
          elevation: 0,
          backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          foregroundColor: isDark ? AppColors.textDark : AppColors.textLight,
          automaticallyImplyLeading: _downloadedFile != null || _downloadError != null,
        ),
        body: FutureBuilder<void>(
          future: _downloadFuture,
          builder: (context, snapshot) {
            if (_downloadState == DownloadFlowState.downloading || snapshot.connectionState == ConnectionState.waiting) {
              return _buildDownloadingUI(isDark);
            }
            if (_downloadState == DownloadFlowState.failed ||
                _downloadState == DownloadFlowState.cancelled ||
                _downloadError != null) {
              return _buildErrorUI(
                isDark,
                cancelled: _downloadState == DownloadFlowState.cancelled,
              );
            }
            return _buildSuccessUI(isDark);
          },
        ),
      ),
    );
  }

  Widget _buildDownloadingUI(bool isDark) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated icon
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primaryLight,
                      AppColors.secondaryLight,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: Icon(
                    Icons.download,
                    size: 50,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Status text
              Text(
                'Downloading...',
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.textDark : AppColors.textLight,
                ),
              ),
              const SizedBox(height: 16),

              Text(
                widget.mode == 'audio'
                    ? 'Your audio is being downloaded'
                    : 'Your video is being downloaded',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(
                  value: _progress == null ? null : (_progress!.percent / 100),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.primaryLight,
                  ),
                  strokeWidth: 4,
                ),
              ),
              const SizedBox(height: 16),

              if (_progress != null)
                Text(
                  '${_progress!.percent}%',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.textDark
                        : AppColors.textLight,
                  ),
                ),

              const SizedBox(height: 12),

              if (_progress != null)
                Text(
                  'Speed: ${_progress!.speed} • ETA: ${_progress!.eta}',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),

              const SizedBox(height: 14),

              Text(
                widget.mode == 'audio'
                    ? 'Audio • MP3 192 kbps'
                    : 'Quality: ${widget.quality}p',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: _cancelDownload,
                icon: const Icon(Icons.close),
                label: const Text('Cancel'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.errorLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessUI(bool isDark) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Success icon
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.successLight.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: Icon(
                    Icons.check_circle,
                    size: 60,
                    color: AppColors.successLight,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Success message
              Text(
                'Nezzlet',
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.textDark : AppColors.textLight,
                ),
              ),
              const SizedBox(height: 16),

              Text(
                widget.mode == 'audio'
                    ? 'Nezzlet successfully.'
                    : 'Nezzlet successfully.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: 8),

              if (_downloadedFile != null)
                GestureDetector(
                  onTap: () => _openDownloadedFile(_downloadedFile!),
                  child: Builder(builder: (context) {
                    final pythonService =
                        Provider.of<PythonService>(context, listen: false);
                    final displayPath =
                        pythonService.lastDownloadResult?['display_path']?.toString();
                    return Text(
                      'Saved to: ${displayPath ?? _downloadedFile}',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: AppColors.primaryLight,
                        decoration: TextDecoration.underline,
                      ),
                    );
                  }),
                ),
              const SizedBox(height: 32),

              // Buttons
              Column(
                children: [
                  if (_downloadedFile != null)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _openDownloadedFile(_downloadedFile!),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryLight,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          widget.mode == 'audio' ? 'ASMAHA AUDIO' : 'SHOFHA VIDEO',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (context) => const HomeScreen(),
                          ),
                          (route) => false,
                        );
                      },
                      child: Text(
                        'NAZZEL TANY!',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorUI(bool isDark, {bool cancelled = false}) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Error icon
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.errorLight.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: Icon(
                    Icons.error_outline,
                    size: 60,
                    color: AppColors.errorLight,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Error message
              Text(
                cancelled ? 'Download Cancelled' : 'Download Failed',
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.textDark : AppColors.textLight,
                ),
              ),
              const SizedBox(height: 16),

              Text(
                _downloadError ?? 'An unknown error occurred',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AppColors.errorLight,
                ),
              ),
              const SizedBox(height: 32),

              // Action buttons
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (context) => const HomeScreen(),
                      ),
                      (route) => false,
                    );
                  },
                  child: Text(
                    'TRY ANOTHER URL',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
