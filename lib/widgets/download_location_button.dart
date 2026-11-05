import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_strings.dart';
import '../services/python_service.dart';
import '../services/runtime_platform.dart';

class DownloadLocationButton extends StatefulWidget {
  final String? file;
  final String? folder;
  final String platform;
  final bool labelled;
  final List<String>? files;
  final VoidCallback? onExpired;
  const DownloadLocationButton(
      {super.key,
      this.file,
      this.folder,
      this.files,
      this.onExpired,
      this.platform = 'youtube',
      this.labelled = false});

  @override
  State<DownloadLocationButton> createState() => _DownloadLocationButtonState();
}

class _DownloadLocationButtonState extends State<DownloadLocationButton> {
  bool _opening = false;
  Future<void> _open() async {
    setState(() => _opening = true);
    try {
      await context.read<PythonService>().openDownloadLocation(
          file: widget.file,
          folder: widget.folder,
          platform: widget.platform,
          files: widget.files);
    } catch (e) {
      if (e is WebFileExpiredException) widget.onExpired?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppStrings.of(context).errorMessage(e.toString()))));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final public = context.read<PythonService>().isPublicWeb;
    final label = public
        ? widget.file == null
            ? (s.isAr ? 'حفظ البلايليست ZIP' : 'Save playlist ZIP')
            : (s.isAr ? 'حفظ على جهازك' : 'Save to your device')
        : RuntimePlatform.isIOS
            ? (s.isAr ? 'فتح أو مشاركة الملفات' : 'Open or share files')
            : s.isAr
                ? 'فتح مكان الملف'
                : 'Open file location';
    final icon = _opening
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2))
        : Icon(public ? Icons.download_rounded : Icons.folder_open_rounded);
    return widget.labelled
        ? TextButton.icon(
            onPressed: _opening ? null : _open, icon: icon, label: Text(label))
        : IconButton(
            tooltip: label, onPressed: _opening ? null : _open, icon: icon);
  }
}
