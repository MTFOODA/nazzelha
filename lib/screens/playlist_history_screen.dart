import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_strings.dart';
import '../services/playlist_controller.dart';
import '../services/python_service.dart';
import '../widgets/app_settings_actions.dart';
import 'playlist_screen.dart';

class PlaylistHistoryScreen extends StatelessWidget {
  const PlaylistHistoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlaylistController>();
    final ar = AppStrings.of(context).isAr;
    final public = context.read<PythonService>().isPublicWeb;
    final items = c.history;
    return Scaffold(
      appBar: AppBar(
          title: Text(ar ? 'سجل البلايليستات' : 'Playlist history'),
          actions: const [AppSettingsActions(), SizedBox(width: 8)]),
      body: items.isEmpty
          ? Center(
              child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                      ar
                          ? 'البلايليستات التي تضيفها ستظهر هنا.'
                          : 'Your playlists will appear here.',
                      textAlign: TextAlign.center)))
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final saved = items[index];
                        final entries =
                            PlaylistController.visibleEntries(saved);
                        final completed = entries
                            .where((e) => e['status'] == 'completed')
                            .length;
                        final stopped = entries
                            .where((e) =>
                                e['status'] != 'completed' &&
                                e['status'] != 'downloading')
                            .length;
                        final active = saved['status'] == 'running';
                        return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                                key: ValueKey('history-${saved['id']}'),
                                contentPadding:
                                    const EdgeInsetsDirectional.fromSTEB(
                                        16, 10, 8, 10),
                                leading: Icon(active
                                    ? Icons.downloading_rounded
                                    : Icons.video_library_outlined),
                                title: Text(saved['title']?.toString() ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(public
                                        ? (ar
                                            ? 'جاهز للحفظ $completed · متبقي أو متوقف $stopped'
                                            : '$completed ready to save · $stopped remaining or stopped')
                                        : ar
                                            ? 'تم تحميل $completed · متبقي أو متوقف $stopped${active ? ' · قيد التنزيل' : ''}'
                                            : '$completed downloaded · $stopped remaining or stopped${active ? ' · Downloading' : ''}')),
                                trailing: IconButton(
                                    tooltip: ar
                                        ? 'إزالة من السجل'
                                        : 'Remove from history',
                                    onPressed: active
                                        ? null
                                        : () async {
                                            final remove = await showDialog<
                                                    bool>(
                                                context: context,
                                                builder: (ctx) => AlertDialog(
                                                        title: Text(ar
                                                            ? 'إزالة من السجل؟'
                                                            : 'Remove from history?'),
                                                        content: Text(ar
                                                            ? 'ستبقى الملفات التي تم تنزيلها على جهازك.'
                                                            : 'Downloaded files will stay on your device.'),
                                                        actions: [
                                                          TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                      ctx,
                                                                      false),
                                                              child: Text(ar
                                                                  ? 'رجوع'
                                                                  : 'Keep')),
                                                          TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                      ctx,
                                                                      true),
                                                              child: Text(ar
                                                                  ? 'إزالة'
                                                                  : 'Remove'))
                                                        ]));
                                            if (remove == true) {
                                              c.removeHistory(
                                                  saved['id'].toString());
                                            }
                                          },
                                    icon: const Icon(
                                        Icons.delete_outline_rounded)),
                                onTap: () {
                                  c.select(saved['id'].toString());
                                  Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                          builder: (_) => const PlaylistScreen(
                                              historyDetail: true)));
                                }));
                      }))),
    );
  }
}
