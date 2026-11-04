import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_strings.dart';
import '../theme/locale_provider.dart';
import '../theme/theme_provider.dart';
import 'app_motion.dart';
import '../screens/developer_screen.dart';

class AppSettingsActions extends StatelessWidget {
  const AppSettingsActions({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
          key: const ValueKey('about-developer'),
          tooltip: s.isAr ? 'عن المطور' : 'About the developer',
          icon: const Icon(Icons.info_outline_rounded),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const DeveloperScreen()))),
      IconButton(
          key: const ValueKey('toggle-language'),
          tooltip: s.languageToggle,
          onPressed: () => context.read<LocaleProvider>().toggle(),
          icon: const Icon(Icons.language_rounded)),
      IconButton(
          key: const ValueKey('toggle-theme'),
          tooltip: s.text(dark ? 'Light mode' : 'Dark mode'),
          onPressed: () => context.read<ThemeProvider>().toggleTheme(),
          icon: AnimatedSwitcher(
              duration: motionDuration(context),
              child: Icon(
                  dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  key: ValueKey(dark)))),
    ]);
  }
}
