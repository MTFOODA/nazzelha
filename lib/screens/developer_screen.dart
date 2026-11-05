import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_strings.dart';
import '../models/app_release.dart';
import '../widgets/app_motion.dart';
import '../widgets/app_statistics_card.dart';

class DeveloperScreen extends StatefulWidget {
  const DeveloperScreen({super.key});
  @override
  State<DeveloperScreen> createState() => _DeveloperScreenState();
}

class _DeveloperScreenState extends State<DeveloperScreen> {
  late AppEdition _edition;
  @override
  void initState() {
    super.initState();
    _edition = switch (defaultTargetPlatform) {
      TargetPlatform.android => AppEdition.android,
      _ => AppEdition.windows,
    };
  }

  Future<void> _open(Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not open link');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppStrings.of(context).isAr
                ? 'تعذّر فتح الرابط. حاول مرة أخرى.'
                : 'Could not open the link. Please try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = AppStrings.of(context).isAr;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(ar ? 'عن المطور' : 'About the developer')),
      body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(padding: const EdgeInsets.all(24), children: [
                const SizedBox(height: 12),
                Center(
                    child: Image.asset('assets/logo/nazzelha-v2.png',
                        width: 88, height: 88)),
                const SizedBox(height: 20),
                Text(ar ? 'نزلها' : 'Nazzelha',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium),
                const SizedBox(height: 6),
                Text('${ar ? 'الإصدار' : 'Version'} ${AppRelease.version}',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 28),
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(ar ? 'تطوير' : 'Developed by',
                                  style: theme.textTheme.labelLarge),
                              const SizedBox(height: 8),
                              Text(ar ? 'محمد فودة' : AppRelease.developer,
                                  style: theme.textTheme.headlineSmall),
                              const SizedBox(height: 20),
                              Wrap(spacing: 12, runSpacing: 8, children: [
                                OutlinedButton.icon(
                                    key: const ValueKey('developer-github'),
                                    onPressed: () => _open(AppRelease.github),
                                    icon: Image.asset(
                                        theme.brightness == Brightness.dark
                                            ? 'assets/brands/github-white.png'
                                            : 'assets/brands/github-black.png',
                                        width: 24,
                                        height: 24,
                                        excludeFromSemantics: true),
                                    label: const Text('GitHub')),
                                OutlinedButton.icon(
                                    key: const ValueKey('developer-linkedin'),
                                    onPressed: () => _open(AppRelease.linkedin),
                                    icon: Image.asset(
                                        'assets/brands/linkedin.png',
                                        width: 24,
                                        height: 24,
                                        excludeFromSemantics: true),
                                    label: const Text('LinkedIn')),
                              ]),
                            ]))),
                const SizedBox(height: 18),
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(ar ? 'حمّل التطبيق' : 'Get the app',
                                  style: theme.textTheme.titleLarge),
                              const SizedBox(height: 8),
                              Text(
                                  ar
                                      ? 'اختار النسخة المناسبة لجهازك.'
                                      : 'Choose the edition for your device.',
                                  style: TextStyle(
                                      color:
                                          theme.colorScheme.onSurfaceVariant)),
                              const SizedBox(height: 20),
                              Row(children: [
                                Expanded(
                                    child: _editionButton(
                                        AppEdition.windows,
                                        'Windows',
                                        Icons.desktop_windows_rounded)),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: _editionButton(AppEdition.android,
                                        'Android', Icons.android_rounded)),
                              ]),
                              const SizedBox(height: 18),
                              AppActionButton(
                                  key: const ValueKey('download-app'),
                                  onPressed: () =>
                                      _open(AppRelease.url(_edition)),
                                  icon: Icons.download_rounded,
                                  label: ar ? 'تحميل النسخة' : 'Download app'),
                              const SizedBox(height: 12),
                              Text(
                                  _edition == AppEdition.windows
                                      ? (ar
                                          ? 'فك ضغط الملف ثم شغّل Nazzelha.exe.'
                                          : 'Extract the ZIP, then open Nazzelha.exe.')
                                      : (ar
                                          ? 'ملف APK لأجهزة أندرويد.'
                                          : 'APK for Android devices.'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant)),
                            ]))),
                const SizedBox(height: 18),
                const AppStatisticsCard(),
              ]))),
    );
  }

  Widget _editionButton(AppEdition edition, String label, IconData icon) {
    final selected = _edition == edition;
    final theme = Theme.of(context);
    return Semantics(
        selected: selected,
        child: PressMotion(
            child: OutlinedButton.icon(
          key: ValueKey('edition-${edition.name}'),
          onPressed: () => setState(() => _edition = edition),
          icon: Icon(icon, size: 20),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            backgroundColor: selected
                ? theme.colorScheme.primary.withValues(alpha: .12)
                : null,
            side: BorderSide(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        )));
  }
}
