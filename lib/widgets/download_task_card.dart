import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_strings.dart';
import '../models/download_task.dart';
import '../services/download_paths.dart';
import '../theme/colors.dart';
import 'custom_dropdown.dart';

/// A compact, self-contained download container for the Nazzelha Sawa queue.
class DownloadTaskCard extends StatefulWidget {
  final DownloadTask task;
  final bool editable;
  final void Function(String platform) onPlatformChanged;
  final void Function(String url) onUrlChanged;
  final void Function(String filename) onFilenameChanged;
  final void Function(String mode) onModeChanged;
  final Future<void> Function() onStart;
  final Future<void> Function() onResume;
  final Future<void> Function() onRemove;

  const DownloadTaskCard({
    super.key,
    required this.task,
    required this.editable,
    required this.onPlatformChanged,
    required this.onUrlChanged,
    required this.onFilenameChanged,
    required this.onModeChanged,
    required this.onStart,
    required this.onResume,
    required this.onRemove,
  });

  @override
  State<DownloadTaskCard> createState() => _DownloadTaskCardState();
}

class _DownloadTaskCardState extends State<DownloadTaskCard> {
  late final TextEditingController _urlController;
  late final TextEditingController _filenameController;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.task.url);
    _filenameController = TextEditingController(text: widget.task.filename);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _filenameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final strings = AppStrings.of(context);
    final task = widget.task;
    final statusColor = _statusColor(task.status);
    final editable = widget.editable;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _statusPill(task.status, statusColor, strings),
                const Spacer(),
                IconButton(
                  tooltip: strings.remove,
                  icon: const Icon(Icons.close, size: 20),
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                  onPressed: () async => widget.onRemove(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: CustomDropdown<String>(
                    value: task.platform,
                    items: DownloadPaths.supportedPlatforms,
                    itemLabels: DownloadPaths.supportedPlatforms
                        .map((p) => strings.platformName(p))
                        .toList(),
                    onChanged: editable ? widget.onPlatformChanged : (_) {},
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _modeSelector(task.mode, editable, strings),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              enabled: editable,
              decoration: InputDecoration(
                hintText: strings.pasteLink,
                isDense: true,
              ),
              keyboardType: TextInputType.url,
              onChanged: widget.onUrlChanged,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _filenameController,
              enabled: editable,
              decoration: InputDecoration(
                labelText: strings.saveAs,
                hintText: strings.optionalFilename,
                isDense: true,
              ),
              onChanged: widget.onFilenameChanged,
            ),
            if (_errorText(task, strings) != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorText(task, strings)!,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: isDark ? AppColors.errorDark : AppColors.errorLight,
                ),
              ),
            ],
            const SizedBox(height: 12),
            _progressArea(task, isDark),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _startOrResume(task, strings)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String? _errorText(DownloadTask task, AppStrings strings) {
    if (task.errorCode != null && task.errorCode!.isNotEmpty) {
      return strings.validationMessage(
        task.errorCode,
        detected: task.errorDetail,
        selected: task.platform,
      );
    }
    if (task.error != null && task.error!.isNotEmpty) {
      return task.error;
    }
    return null;
  }

  Widget _modeSelector(String mode, bool editable, AppStrings strings) {
    final videoSelected = mode == 'video';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _modeButton(
          label: strings.videoMode,
          selected: videoSelected,
          enabled: editable,
          onTap: () => widget.onModeChanged('video'),
        ),
        const SizedBox(height: 6),
        _modeButton(
          label: strings.audioMode,
          selected: !videoSelected,
          enabled: editable,
          onTap: () => widget.onModeChanged('audio'),
        ),
      ],
    );
  }

  Widget _modeButton({
    required String label,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return OutlinedButton(
      onPressed: enabled ? onTap : null,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        minimumSize: const Size(0, 0),
        backgroundColor: selected
            ? AppColors.primaryLight.withValues(alpha: 0.12)
            : null,
        side: BorderSide(
          color: selected
              ? AppColors.primaryLight
              : (isDark ? AppColors.borderDark : AppColors.borderLight),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: selected ? AppColors.primaryLight : null,
        ),
      ),
    );
  }

  Widget _statusPill(TaskStatus status, Color color, AppStrings strings) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        strings.statusLabel(status),
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _progressArea(DownloadTask task, bool isDark) {
    final showProgress = task.status.isActive || task.progress > 0;
    if (!showProgress) return const SizedBox.shrink();

    final known = task.progressKnown;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: known ? (task.progress.clamp(0, 100) / 100.0) : null,
              minHeight: 6,
              backgroundColor:
                  isDark ? AppColors.surfaceDark : AppColors.borderLight,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          known ? '${task.progress.clamp(0, 100)}%' : '…',
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
          ),
        ),
      ],
    );
  }

  Widget _startOrResume(DownloadTask task, AppStrings strings) {
    final needsResume = task.status == TaskStatus.paused ||
        task.status == TaskStatus.failed ||
        task.status == TaskStatus.cancelled;
    final canAct = needsResume ||
        task.status == TaskStatus.pending;

    if (task.status.isActive ||
        task.status == TaskStatus.queued ||
        task.status == TaskStatus.completed) {
      return const SizedBox.shrink();
    }

    final label = needsResume ? strings.resume : strings.start;
    final onPressed = needsResume ? widget.onResume : widget.onStart;
    return ElevatedButton.icon(
      onPressed: canAct ? () async => onPressed() : null,
      icon: const Icon(Icons.play_arrow, size: 18),
      label: Text(
        label,
        style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }

  static Color _statusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return AppColors.textSecondaryLight;
      case TaskStatus.queued:
        return AppColors.warningLight;
      case TaskStatus.downloading:
      case TaskStatus.merging:
        return AppColors.primaryLight;
      case TaskStatus.paused:
        return AppColors.warningLight;
      case TaskStatus.completed:
        return AppColors.successLight;
      case TaskStatus.failed:
        return AppColors.errorLight;
      case TaskStatus.cancelled:
        return AppColors.textSecondaryLight;
    }
  }
}
