import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_strings.dart';
import '../services/playlist_controller.dart';
import '../services/python_service.dart';
import '../widgets/app_settings_actions.dart';
import '../widgets/app_motion.dart';
import '../widgets/download_location_button.dart';

class PlaylistScreen extends StatefulWidget {
  final bool historyDetail;
  const PlaylistScreen({super.key, this.historyDetail = false});
  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  final _url = TextEditingController();
  final _folder = TextEditingController();
  String? _jobId;
  @override
  void dispose() {
    _url.dispose();
    _folder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlaylistController>();
    final public = context.read<PythonService>().isPublicWeb;
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    String t(String en, String ar) => s.isAr ? ar : en;
    final entries = c.entries;
    final id = c.job?['id']?.toString();
    if (id != _jobId) {
      _jobId = id;
      _folder.text = c.folder;
      if (c.job != null) _url.text = c.job!['url']?.toString() ?? _url.text;
    } else if (c.running && _folder.text != c.folder) {
      _folder.text = c.folder;
    }
    final available = entries.where((e) => e['unavailable'] != true).length;
    final activeProgress = entries
        .where((e) => e['status'] == 'downloading')
        .fold<double>(
            0, (total, e) => total + ((e['progress'] as num? ?? 0) / 100));
    final progress = available == 0
        ? 0.0
        : ((c.completed + activeProgress) / available).clamp(0.0, 1.0);
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.historyDetail
              ? (c.job?['title']?.toString() ?? t('History', 'السجل'))
              : t('YouTube playlist', 'بلاي ليست يوتيوب')),
          actions: const [AppSettingsActions(), SizedBox(width: 8)]),
      body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: CustomScrollView(slivers: [
                SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    sliver: SliverToBoxAdapter(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                          if (!widget.historyDetail) ...[
                            Text(
                                t('All videos, best available quality',
                                    'كل الفيديوهات بأفضل جودة متاحة'),
                                style: theme.textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            Text(
                                t('Paste a YouTube playlist link, preview its videos and choose a folder.',
                                    'الصق رابط بلاي ليست يوتيوب، راجع الفيديوهات واختار اسم المجلد.'),
                                style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 22),
                            Card(
                                child: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          TextField(
                                              key: const ValueKey(
                                                  'playlist-url'),
                                              controller: _url,
                                              enabled: !c.anyRunning &&
                                                  !c.loading,
                                              textDirection: TextDirection.ltr,
                                              keyboardType: TextInputType.url,
                                              autocorrect: false,
                                              enableSuggestions: false,
                                              decoration: InputDecoration(
                                                  labelText: t(
                                                      'YouTube playlist URL',
                                                      'رابط بلاي ليست يوتيوب'),
                                                  hintText:
                                                      'https://youtube.com/playlist?list=…',
                                                  prefixIcon: const Icon(
                                                      Icons.link_rounded)),
                                              onSubmitted:
                                                  c.anyRunning || c.loading
                                                      ? null
                                                      : (_) =>
                                                          c.extract(_url.text)),
                                          const SizedBox(height: 14),
                                          AppActionButton(
                                              key: const ValueKey(
                                                  'playlist-extract'),
                                              onPressed: c.anyRunning ||
                                                      c.loading
                                                  ? null
                                                  : () => c.extract(_url.text),
                                              busy: c.loading,
                                              icon: Icons
                                                  .playlist_add_check_rounded,
                                              label: t('Extract videos',
                                                  'استخراج الفيديوهات')),
                                        ]))),
                          ],
                          if (c.error != null)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                child: Text(s.errorMessage(c.error!),
                                    style: TextStyle(
                                        color: theme.colorScheme.error))),
                          if (c.job != null) ...[
                            const SizedBox(height: 22),
                            Text(c.job!['title']?.toString() ?? '',
                                style: theme.textTheme.titleLarge),
                            const SizedBox(height: 14),
                            TextField(
                                key: const ValueKey('playlist-folder'),
                                controller: _folder,
                                readOnly: c.folderLocked,
                                onChanged: c.setFolder,
                                decoration: InputDecoration(
                                    labelText: t('Playlist folder name',
                                        'اسم مجلد البلاي ليست'),
                                    prefixIcon:
                                        const Icon(Icons.folder_outlined),
                                    suffixIcon: c.folderLocked
                                        ? Icon(Icons.lock_outline_rounded,
                                            size: 18,
                                            semanticLabel: t(
                                                'Folder name locked',
                                                'اسم المجلد ثابت'))
                                        : null)),
                            const SizedBox(height: 10),
                            SelectableText(
                                public
                                    ? '${c.folder}.zip'
                                    : 'Downloads/Nazzelha/YouTube/Playlists/${c.folder}',
                                textDirection: TextDirection.ltr,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant)),
                            if (c.completed > 0)
                              Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: DownloadLocationButton(
                                      folder: c.folder,
                                      labelled: true,
                                      files: entries
                                          .where((e) =>
                                              e['status'] == 'completed' &&
                                              e['file'] != null)
                                          .map((e) => e['file'].toString())
                                          .toList())),
                            const SizedBox(height: 20),
                            Row(children: [
                              Expanded(
                                  child: Text(
                                      public
                                          ? t('${c.completed} of ${entries.length} ready to save',
                                              'جاهز للحفظ ${c.completed} من ${entries.length}')
                                          : t('${c.completed} of ${entries.length} downloaded',
                                              'تم تحميل ${c.completed} من ${entries.length}'),
                                      style: theme.textTheme.titleSmall)),
                              Text('${(progress * 100).round()}%',
                                  textDirection: TextDirection.ltr,
                                  style: TextStyle(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w700))
                            ]),
                            const SizedBox(height: 10),
                            LinearProgressIndicator(value: progress),
                            const SizedBox(height: 18),
                            if (c.running)
                              AppActionButton(
                                  outlined: true,
                                  onPressed: c.pause,
                                  icon: Icons.pause_rounded,
                                  label: t('Pause', 'إيقاف مؤقت'))
                            else
                              AppActionButton(
                                  key: const ValueKey('playlist-download'),
                                  onPressed: c.hasRemaining && c.canStart
                                      ? c.start
                                      : null,
                                  icon: Icons.download_rounded,
                                  label: c.completed > 0 ||
                                          c.job!['status'] == 'paused' ||
                                          c.job!['status'] == 'partial'
                                      ? t('Resume remaining videos',
                                          'استئناف الفيديوهات المتبقية')
                                      : t('Download all · best quality',
                                          'تحميل الكل · أفضل جودة')),
                            const SizedBox(height: 12),
                            if (public)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(
                                      t('Save ready videos individually or as a ZIP. Temporary files expire after one hour. The free service may take a minute to wake up. Keep this tab open while preparing a playlist.',
                                          'احفظ الفيديوهات الجاهزة منفردة أو كملف ZIP. الملفات المؤقتة تنتهي بعد ساعة. الخدمة المجانية قد تحتاج دقيقة لتبدأ. اترك الصفحة مفتوحة أثناء تجهيز البلايليست.'),
                                      style: theme.textTheme.bodySmall)),
                            if ((c.job!['unavailable'] as num? ?? 0) > 0)
                              Text(t(
                                  '${c.job!['unavailable']} unavailable entries were skipped.',
                                  'تم تخطي ${c.job!['unavailable']} عنصر غير متاح.')),
                            Text(
                                s.text(
                                    'Unavailable videos are marked individually; other videos keep downloading.'),
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 18),
                          ],
                        ]))),
                SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    sliver: SliverList.builder(
                        itemCount: entries.length,
                        itemBuilder: (context, index) =>
                            _entry(entries[index], s))),
              ]))),
    );
  }

  Widget _entry(Map<String, dynamic> entry, AppStrings s) {
    final c = context.read<PlaylistController>();
    final theme = Theme.of(context);
    final status = entry['status']?.toString() ?? 'pending';
    final done = status == 'completed';
    final failed = status == 'failed' || status == 'unavailable';
    final color = failed ? theme.colorScheme.error : theme.colorScheme.primary;
    final label = done && context.read<PythonService>().isPublicWeb
        ? (s.isAr ? 'جاهز للحفظ' : 'Ready to save')
        : s.text({
              'pending': 'Pending',
              'downloading': 'Downloading',
              'completed': 'Completed',
              'failed': 'Failed',
              'paused': 'Paused',
              'unavailable': 'Unavailable'
            }[status] ??
            status);
    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                          radius: 18,
                          backgroundColor: color.withValues(alpha: .12),
                          child: done || failed
                              ? Icon(
                                  done
                                      ? Icons.check_rounded
                                      : Icons.priority_high_rounded,
                                  color: color,
                                  size: 20)
                              : Text('${entry['index']}',
                                  style:
                                      TextStyle(color: color, fontSize: 13))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(entry['title']?.toString() ?? '',
                                style: theme.textTheme.titleSmall),
                            const SizedBox(height: 5),
                            Text(
                                '$label${status == 'downloading' ? ' · ${entry['progress']}%' : ''}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant)),
                            if (status == 'downloading')
                              Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: LinearProgressIndicator(
                                      value: (entry['progress'] as num? ?? 0) /
                                          100)),
                            if (entry['error'] != null)
                              Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                      s.errorMessage(entry['error'].toString()),
                                      style: TextStyle(
                                          color: theme.colorScheme.error))),
                            if (entry['file'] != null &&
                                !context.read<PythonService>().isPublicWeb)
                              Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: SelectableText(
                                      entry['file'].toString(),
                                      textDirection: TextDirection.ltr,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                              color: theme.colorScheme
                                                  .onSurfaceVariant))),
                          ])),
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        if (entry['file'] != null)
                          DownloadLocationButton(
                              file: entry['file'].toString(),
                              folder: c.folder,
                              onExpired: () => c.expireWebFile(
                                  PlaylistController.entryKey(entry))),
                        if (!done && status != 'downloading')
                          IconButton(
                              key: ValueKey(
                                  'resume-${PlaylistController.entryKey(entry)}'),
                              tooltip: s.resume,
                              icon: const Icon(Icons.play_arrow_rounded),
                              onPressed: c.canStart &&
                                      (entry['url']?.toString() ?? '')
                                          .isNotEmpty
                                  ? () => c.resumeEntry(
                                      PlaylistController.entryKey(entry))
                                  : null),
                        IconButton(
                            key: ValueKey(
                                'remove-${PlaylistController.entryKey(entry)}'),
                            tooltip: s.remove,
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: () => c.removeEntry(
                                PlaylistController.entryKey(entry))),
                      ]),
                    ]))));
  }
}
