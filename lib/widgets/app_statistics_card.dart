import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_strings.dart';
import '../services/app_statistics_service.dart';

class AppStatisticsCard extends StatefulWidget {
  const AppStatisticsCard({super.key});
  @override
  State<AppStatisticsCard> createState() => _AppStatisticsCardState();
}

class _AppStatisticsCardState extends State<AppStatisticsCard> {
  late Future<AppStatistics> _statistics;
  @override
  void initState() {
    super.initState();
    _statistics = context.read<AppStatisticsService>().load();
  }

  @override
  Widget build(BuildContext context) {
    final ar = AppStrings.of(context).isAr;
    final theme = Theme.of(context);
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(ar ? 'إحصائيات نزلها' : 'Nazzelha statistics',
                      style: theme.textTheme.titleLarge),
                  const SizedBox(height: 18),
                  FutureBuilder<AppStatistics>(
                      future: _statistics,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                              child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)));
                        }
                        if (!snapshot.hasData) {
                          return Column(children: [
                            Text(ar
                                ? 'الإحصائيات غير متاحة مؤقتًا.'
                                : 'Statistics are temporarily unavailable.'),
                            TextButton.icon(
                                onPressed: () => setState(() => _statistics =
                                    context
                                        .read<AppStatisticsService>()
                                        .load()),
                                icon: const Icon(Icons.refresh_rounded),
                                label: Text(ar ? 'إعادة المحاولة' : 'Retry')),
                          ]);
                        }
                        final stats = snapshot.data!;
                        Widget metric(
                                IconData icon, String label, int? value) =>
                            Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                    color: theme.colorScheme.primary
                                        .withValues(alpha: .06),
                                    borderRadius: BorderRadius.circular(16)),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(icon,
                                          color: theme.colorScheme.primary),
                                      const SizedBox(height: 12),
                                      Text(value?.toString() ?? '—',
                                          style: theme.textTheme.headlineSmall),
                                      const SizedBox(height: 4),
                                      Text(label),
                                    ]));
                        return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              IntrinsicHeight(
                                  child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                    Expanded(
                                        child: metric(
                                            Icons.public_rounded,
                                            ar
                                                ? 'زيارات الموقع'
                                                : 'Website visits',
                                            stats.visits)),
                                    const SizedBox(width: 10),
                                    Expanded(
                                        child: metric(
                                            Icons.desktop_windows_rounded,
                                            ar
                                                ? 'تحميلات Windows'
                                                : 'Windows downloads',
                                            stats.windows)),
                                    const SizedBox(width: 10),
                                    Expanded(
                                        child: metric(
                                            Icons.android_rounded,
                                            ar
                                                ? 'تحميلات Android'
                                                : 'Android downloads',
                                            stats.android)),
                                  ])),
                              const SizedBox(height: 14),
                              Text(
                                  ar
                                      ? 'الزيارات من وقت تفعيل العدّاد. التحميلات من GitHub لكل الإصدارات، وتُحدّث كل ١٥ دقيقة.'
                                      : 'Visits since the counter was enabled. Downloads include all GitHub releases and refresh every 15 minutes.',
                                  style: theme.textTheme.bodySmall),
                              if (stats.stale || stats.windows == null) ...[
                                const SizedBox(height: 8),
                                Text(
                                    stats.windows == null
                                        ? (ar
                                            ? 'إحصائيات التحميل غير متاحة مؤقتًا.'
                                            : 'Download statistics are temporarily unavailable.')
                                        : ar
                                            ? 'تعذّر تحديث التحميلات مؤقتًا؛ تظهر آخر أرقام متاحة.'
                                            : 'Download updates are temporarily unavailable; showing the last available counts.',
                                    style: theme.textTheme.bodySmall),
                              ],
                            ]);
                      }),
                ])));
  }
}
