import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_strings.dart';
import '../screens/developer_screen.dart';

class HostedFailureActions extends StatelessWidget {
  final String url;
  const HostedFailureActions({super.key, required this.url});
  static bool matches(String? error) =>
      error?.contains(
          'YouTube is blocking requests from the hosted download service.') ==
      true;

  @override
  Widget build(BuildContext context) {
    final ar = AppStrings.of(context).isAr;
    return Wrap(spacing: 8, children: [
      TextButton.icon(
          icon: const Icon(Icons.copy_rounded),
          label: Text(ar ? 'نسخ الرابط للتطبيق' : 'Copy link for the app'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(ar ? 'تم نسخ الرابط' : 'Link copied')));
          }),
      TextButton.icon(
          icon: const Icon(Icons.download_rounded),
          label:
              Text(ar ? 'تطبيق Android أو Windows' : 'Get Android or Windows'),
          onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                  builder: (_) => const DeveloperScreen()))),
    ]);
  }
}
