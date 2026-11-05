import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/download_task.dart';
import '../services/queue_controller.dart';
import '../services/python_service.dart';
import '../theme/colors.dart';
import '../widgets/download_task_card.dart';
import '../widgets/app_settings_actions.dart';
import '../widgets/app_motion.dart';

/// Nazzelha — build and run a sequential multi-link download queue.
class NazzelhaScreen extends StatefulWidget {
  const NazzelhaScreen({super.key});

  @override
  State<NazzelhaScreen> createState() => _NazzelhaScreenState();
}

class _NazzelhaScreenState extends State<NazzelhaScreen> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final controller = context.read<NazzelhaQueueController>();
    await controller.load();
    if (mounted) setState(() => _loaded = true);
  }

  void _showValidationError(String code, String? id) {
    if (!mounted) return;
    final controller = context.read<NazzelhaQueueController>();
    final task = id == null ? null : controller.taskById(id);
    final strings = AppStrings.of(context);
    final message = strings.validationMessage(
      code,
      detected: task?.errorDetail,
      selected: task?.platform,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.errorLight),
    );
  }

  Future<void> _handleStart(String id) async {
    final controller = context.read<NazzelhaQueueController>();
    final error = await controller.start(id);
    if (error != null) _showValidationError(error, id);
  }

  Future<void> _handleResume(String id) async {
    final controller = context.read<NazzelhaQueueController>();
    final error = await controller.resume(id);
    if (error != null) _showValidationError(error, id);
  }

  Future<void> _handleRemove(DownloadTask task) async {
    final controller = context.read<NazzelhaQueueController>();
    final strings = AppStrings.of(context);
    if (task.status.isActive) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(strings.cancelDialogTitle),
          content: Text(strings.cancelDialogBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(strings.keep),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(strings.removeAndCancel),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await controller.remove(task.id);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final strings = AppStrings.of(context);
    final controller = context.watch<NazzelhaQueueController>();

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.appTitle),
        actions: const [AppSettingsActions(), SizedBox(width: 8)],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (context.read<PythonService>().browserTransfers)
                  Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Text(
                          strings.isAr
                              ? 'الويب المجاني: حتى ٩٦ ميجابايت للفيديو وحوالي ٤ دقائق لتجهيزه. احفظ الملفات قبل تحديث الصفحة أو إغلاقها.'
                              : 'Free web: up to 96 MB per video and about 4 minutes to prepare it. Save files before reloading or closing this tab.',
                          style: Theme.of(context).textTheme.bodySmall)),
                _addButton(isDark, strings),
                Expanded(
                  child: controller.tasks.isEmpty
                      ? _emptyState(isDark, strings)
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: controller.tasks.length,
                          itemBuilder: (context, index) {
                            final task = controller.tasks[index];
                            return DownloadTaskCard(
                              key: ValueKey(task.id),
                              task: task,
                              editable: controller.canEdit(task),
                              onPlatformChanged: (p) =>
                                  controller.updatePlatform(task.id, p),
                              onUrlChanged: (u) =>
                                  controller.updateUrl(task.id, u),
                              onFilenameChanged: (f) =>
                                  controller.updateFilename(task.id, f),
                              onModeChanged: (m) =>
                                  controller.updateMode(task.id, m),
                              onQualityChanged: (q) =>
                                  controller.updateQuality(task.id, q),
                              onFetchQualities: () =>
                                  controller.fetchQualities(task.id),
                              onStart: () => _handleStart(task.id),
                              onResume: () => _handleResume(task.id),
                              onRemove: () => _handleRemove(task),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _addButton(bool isDark, AppStrings strings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: SizedBox(
        width: double.infinity,
        child: AppActionButton(
            label: strings.add,
            icon: Icons.add_rounded,
            onPressed: () => context.read<NazzelhaQueueController>().addTask()),
      ),
    );
  }

  Widget _emptyState(bool isDark, AppStrings strings) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.playlist_add,
              size: 64,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
            const SizedBox(height: 16),
            Text(
              strings.emptyTitle,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.textDark : AppColors.textLight,
              ).copyWith(fontFamilyFallback: const ['Tajawal']),
            ),
            const SizedBox(height: 8),
            Text(
              strings.emptyBody,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ).copyWith(fontFamilyFallback: const ['Tajawal']),
            ),
          ],
        ),
      ),
    );
  }
}
