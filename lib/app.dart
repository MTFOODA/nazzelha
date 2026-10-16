import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'theme/locale_provider.dart';
import 'theme/theme_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/main_shell.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return Consumer<LocaleProvider>(
          builder: (context, localeProvider, _) {
            return MaterialApp(
              title: 'Nazzelha',
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeProvider.themeMode,
              locale: localeProvider.locale,
              supportedLocales: const [Locale('en'), Locale('ar')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: const SplashScreen(),
              routes: {
                '/home': (context) => const MainShell(),
              },
              debugShowCheckedModeBanner: false,
            );
          },
        );
      },
    );
  }
}
