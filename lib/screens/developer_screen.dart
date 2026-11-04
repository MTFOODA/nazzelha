import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_strings.dart';
import '../models/app_release.dart';
import '../widgets/app_motion.dart';

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
      TargetPlatform.iOS => AppEdition.iosWeb,
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
    final ios = _edition == AppEdition.iosWeb;
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
                                    icon: const Icon(Icons.code_rounded),
                                    label: const Text('GitHub')),
                                OutlinedButton.icon(
                                    key: const ValueKey('developer-linkedin'),
                                    onPressed: () => _open(AppRelease.linkedin),
                                    icon:
                                        const Icon(Icons.work_outline_rounded),
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
                              DropdownButtonFormField<AppEdition>(
                                  key: const ValueKey('app-edition'),
                                  initialValue: _edition,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                      labelText: ar ? 'النسخة' : 'Edition'),
                                  items: [
                                    const DropdownMenuItem(
                                        value: AppEdition.windows,
                                        child: Text('Windows · ZIP')),
                                    const DropdownMenuItem(
                                        value: AppEdition.android,
                                        child: Text('Android · APK')),
                                    DropdownMenuItem(
                                        value: AppEdition.iosWeb,
                                        child: Text(ar
                                            ? 'iPhone / iPad · ويب'
                                            : 'iPhone / iPad · Web')),
                                  ],
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() => _edition = value);
                                    }
                                  }),
                              const SizedBox(height: 18),
                              AppActionButton(
                                  key: const ValueKey('download-app'),
                                  onPressed: () =>
                                      _open(AppRelease.url(_edition)),
                                  icon: ios
                                      ? Icons.open_in_browser_rounded
                                      : Icons.download_rounded,
                                  label: ios
                                      ? (ar ? 'فتح نسخة الويب' : 'Open web app')
                                      : (ar ? 'تحميل النسخة' : 'Download app')),
                              const SizedBox(height: 12),
                              Text(
                                  ios
                                      ? (ar
                                          ? 'لا توجد نسخة iOS أصلية حاليًا. افتح الموقع في Safari واختر «إضافة إلى الشاشة الرئيسية» لاستخدام نسخة الويب.'
                                          : 'A native iOS edition is not available yet. Open the website in Safari and choose Add to Home Screen to use the web app.')
                                      : _edition == AppEdition.windows
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
              ]))),
    );
  }
}
