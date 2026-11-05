import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/download_task.dart';
import '../services/download_paths.dart';
import '../services/python_service.dart';
import '../services/queue_controller.dart';
import '../theme/colors.dart';
import 'custom_dropdown.dart';
import 'app_motion.dart';
import 'download_location_button.dart';
import 'hosted_failure_actions.dart';

/// A compact, self-contained download container for the Nazzelha queue.
class DownloadTaskCard extends StatefulWidget {
  final DownloadTask task;
  final bool editable;
  final void Function(String platform) onPlatformChanged;
  final void Function(String url) onUrlChanged;
  final void Function(String filename) onFilenameChanged;
  final void Function(String mode) onModeChanged;
  final void Function(int quality) onQualityChanged;
  final Future<void> Function() onFetchQualities;
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
    required this.onQualityChanged,
    required this.onFetchQualities,
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
                    enabled: editable,
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
              textDirection: TextDirection.ltr,
              enabled: editable,
              decoration: InputDecoration(
                hintText: strings.pasteLink,
                isDense: true,
              ),
              keyboardType: TextInputType.url,
              onChanged: widget.onUrlChanged,
            ),
            const SizedBox(height: 12),
            if (task.mode == 'video') ...[
              Row(children: [
                Expanded(
                    child: DropdownButtonFormField<int>(
                        key: ValueKey(
                            '${task.id}-${task.quality}-${task.availableQualities.join(',')}'),
                        initialValue: task.quality,
                        isExpanded: true,
                        decoration: InputDecoration(
                            labelText: strings.isAr ? 'الجودة' : 'Quality',
                            isDense: true),
                        items: {
                          DownloadPaths.bestQuality,
                          ...task.availableQualities,
                          task.quality
                        }
                            .map((q) => DropdownMenuItem(
                                value: q,
                                child: Text(q == DownloadPaths.bestQuality
                                    ? strings.text('Best available')
                                    : '${q}p')))
                            .toList(),
                        onChanged: editable && !task.loadingQualities
                            ? (q) {
                                if (q != null) widget.onQualityChanged(q);
                              }
                            : null)),
                const SizedBox(width: 8),
                IconButton(
                    tooltip: strings.isAr
                        ? 'عرض الجودات المتاحة'
                        : 'Find available qualities',
                    onPressed: editable && !task.loadingQualities
                        ? widget.onFetchQualities
                        : null,
                    icon: task.loadingQualities
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh_rounded)),
              ]),
              if (task.qualityError != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(strings.errorMessage(task.qualityError!),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
              const SizedBox(height: 12),
            ],
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
                ).copyWith(fontFamilyFallback: const ['Tajawal']),
              ),
            ],
            const SizedBox(height: 12),
            if (HostedFailureActions.matches(task.error) ||
                HostedFailureActions.matches(task.qualityError))
              HostedFailureActions(url: task.url),
            _progressArea(task, isDark),
            if (task.outputFile != null && task.status == TaskStatus.completed)
              DownloadLocationButton(
                  file: task.outputFile,
                  onExpired: () => context
                      .read<NazzelhaQueueController>()
                      .expireWebFile(task.id),
                  platform: task.platform,
                  labelled: true),
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
      return strings.errorMessage(task.error!);
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
    return PressMotion(
        enabled: enabled,
        child: OutlinedButton(
          onPressed: enabled ? onTap : null,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            minimumSize: const Size(0, 0),
            backgroundColor: selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                : null,
            side: BorderSide(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : (isDark ? AppColors.borderDark : AppColors.borderLight),
            ),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? Theme.of(context).colorScheme.primary : null,
            ).copyWith(fontFamilyFallback: const ['Tajawal']),
          ),
        ));
  }

  Widget _statusPill(TaskStatus status, Color color, AppStrings strings) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status == TaskStatus.completed &&
                context.read<PythonService>().isPublicWeb
            ? (strings.isAr ? 'جاهز للحفظ' : 'Ready to save')
            : strings.statusLabel(status),
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ).copyWith(fontFamilyFallback: const ['Tajawal']),
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
          ).copyWith(fontFamilyFallback: const ['Tajawal']),
        ),
      ],
    );
  }

  Widget _startOrResume(DownloadTask task, AppStrings strings) {
    final needsResume = task.status == TaskStatus.paused ||
        task.status == TaskStatus.failed ||
        task.status == TaskStatus.cancelled;
    final canAct = !task.loadingQualities &&
        (needsResume || task.status == TaskStatus.pending);

    if (task.status.isActive ||
        task.status == TaskStatus.queued ||
        task.status == TaskStatus.completed) {
      return const SizedBox.shrink();
    }

    final label = needsResume ? strings.resume : strings.start;
    final onPressed = needsResume ? widget.onResume : widget.onStart;
    return AppActionButton(
        label: label,
        icon: Icons.play_arrow_rounded,
        onPressed: canAct ? () async => onPressed() : null);
  }

  Color _statusColor(TaskStatus status) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    switch (status) {
      case TaskStatus.pending:
        return Theme.of(context).colorScheme.onSurfaceVariant;
      case TaskStatus.queued:
        return dark ? AppColors.warningDark : const Color(0xFF925A00);
      case TaskStatus.downloading:
      case TaskStatus.merging:
        return Theme.of(context).colorScheme.primary;
      case TaskStatus.paused:
        return dark ? AppColors.warningDark : const Color(0xFF925A00);
      case TaskStatus.completed:
        return dark ? AppColors.successDark : const Color(0xFF067454);
      case TaskStatus.failed:
        return Theme.of(context).colorScheme.error;
      case TaskStatus.cancelled:
        return AppColors.textSecondaryLight;
    }
  }
}
