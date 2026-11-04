import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nazzelha/app.dart';
import 'package:nazzelha/screens/playlist_screen.dart';
import 'package:nazzelha/screens/nazzelha_screen.dart';
import 'package:nazzelha/services/playlist_controller.dart';
import 'package:nazzelha/services/python_service.dart';
import 'package:nazzelha/services/queue_controller.dart';
import 'package:nazzelha/theme/app_theme.dart';
import 'package:nazzelha/theme/locale_provider.dart';
import 'package:nazzelha/theme/theme_provider.dart';
import 'package:nazzelha/widgets/app_motion.dart';
import 'package:nazzelha/screens/developer_screen.dart';
import 'package:nazzelha/models/app_release.dart';
import 'support/ui_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final arabic = FontLoader('Tajawal')
      ..addFont(rootBundle.load('assets/fonts/Tajawal-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Tajawal-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Tajawal-Bold.ttf'));
    await arabic.load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    AppTheme.lightTheme;
    await GoogleFonts.pendingFonts();
  });

  for (final spec in [
    (width: 390.0, dark: false, ar: false),
    (width: 390.0, dark: true, ar: true),
    (width: 1200.0, dark: false, ar: true),
    (width: 1200.0, dark: true, ar: false),
  ]) {
    testWidgets(
        'navigation, theme and language ${spec.width} dark=${spec.dark} ar=${spec.ar}',
        (tester) async {
      tester.view.physicalSize = Size(spec.width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues(
          {'appLocale': spec.ar ? 'ar' : 'en', 'isDarkMode': spec.dark});
      final python = FixturePythonService();
      final playlist = PlaylistController(python);
      await playlist.load();
      await seedPlaylist(playlist);
      final queue = NazzelhaQueueController(
          python: python, logger: Logger(level: Level.off));
      final theme = ThemeProvider();
      final locale = LocaleProvider();
      const boundaryKey = ValueKey('app-capture');
      await tester.pumpWidget(MultiProvider(providers: [
        Provider<PythonService>.value(value: python),
        ChangeNotifierProvider.value(value: playlist),
        ChangeNotifierProvider.value(value: queue),
        ChangeNotifierProvider.value(value: theme),
        ChangeNotifierProvider.value(value: locale),
      ], child: const RepaintBoundary(key: boundaryKey, child: MyApp())));
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();
      expect(find.byType(NazzelhaScreen), findsOneWidget);
      await tester
          .tap(find.byKey(const ValueKey('about-developer')).hitTestable());
      await tester.pumpAndSettle();
      expect(find.byType(DeveloperScreen), findsOneWidget);
      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('LinkedIn'), findsOneWidget);
      expect(
          find.text(spec.ar ? 'محمد فودة' : 'Mohamed Fooda'), findsOneWidget);
      final edition = find.byKey(const ValueKey('app-edition'));
      await tester.ensureVisible(edition);
      await tester.tap(edition);
      await tester.pumpAndSettle();
      await tester.tap(find
          .text(spec.ar ? 'iPhone / iPad · ويب' : 'iPhone / iPad · Web')
          .last);
      await tester.pumpAndSettle();
      expect(
          find.textContaining(spec.ar
              ? 'لا توجد نسخة iOS أصلية'
              : 'A native iOS edition is not available'),
          findsOneWidget);
      expect(
          AppRelease.url(AppEdition.android)
              .path
              .endsWith('Nazzelha-Android.apk'),
          isTrue);
      expect(
          AppRelease.url(AppEdition.windows)
              .path
              .endsWith('Nazzelha-Windows-x64.zip'),
          isTrue);
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.byType(DeveloperScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Platform sessions'), findsNothing);
      expect(find.byTooltip('جلسات المنصات'), findsNothing);
      expect(find.textContaining('Sawa'), findsNothing);
      expect(find.textContaining('سوا'), findsNothing);
      expect(Theme.of(tester.element(find.byType(NazzelhaScreen))).brightness,
          spec.dark ? Brightness.dark : Brightness.light);
      expect(find.byType(NavigationRail),
          spec.width >= 860 ? findsOneWidget : findsNothing);
      expect(find.byType(NavigationBar),
          spec.width < 860 ? findsOneWidget : findsNothing);
      final nav = spec.width >= 860
          ? find.byKey(const ValueKey('nav-1-label'))
          : find.byKey(const ValueKey('nav-1'));
      await tester.tap(nav);
      await tester.pumpAndSettle();
      expect(find.byType(PlaylistScreen), findsOneWidget);
      expect(find.text(spec.ar ? 'بلاي ليست يوتيوب' : 'YouTube playlist'),
          findsOneWidget);
      expect(Directionality.of(tester.element(find.byType(PlaylistScreen))),
          spec.ar ? TextDirection.rtl : TextDirection.ltr);
      expect(tester.takeException(), isNull);
      Future<void> capture(String prefix) => tester.runAsync(() async {
            final boundary = tester
                .renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
            final image = await boundary.toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            final directory = Directory('build/ui_previews')
              ..createSync(recursive: true);
            File('${directory.path}/$prefix${spec.dark ? 'dark' : 'light'}-${spec.ar ? 'ar' : 'en'}-${spec.width.toInt()}.png')
                .writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
      await capture('');
      await tester.tap(spec.width >= 860
          ? find.byKey(const ValueKey('nav-0-label'))
          : find.byKey(const ValueKey('nav-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(spec.ar ? 'إضافة' : 'Add'));
      await tester.pumpAndSettle();
      expect(find.byType(NazzelhaScreen), findsOneWidget);
      expect(queue.tasks.length, 1);
      expect(tester.takeException(), isNull);
      final urlField = find
          .descendant(
              of: find.byType(NazzelhaScreen), matching: find.byType(TextField))
          .first;
      await tester.enterText(
          urlField, 'https://youtube.com/watch?v=abcdefghijk');
      final fetch = find.byTooltip(
          spec.ar ? 'عرض الجودات المتاحة' : 'Find available qualities');
      await tester.ensureVisible(fetch);
      await tester.tap(fetch);
      await tester.pumpAndSettle();
      final quality = find.byType(DropdownButtonFormField<int>);
      await tester.ensureVisible(quality);
      await tester.tap(quality);
      await tester.pumpAndSettle();
      await tester.tap(find.text('720p').last);
      await tester.pumpAndSettle();
      expect(queue.tasks.single.quality, 720);
      await capture('queue-');
      await tester.tap(spec.width >= 860
          ? find.byKey(const ValueKey('nav-2-label'))
          : find.byKey(const ValueKey('nav-2')));
      await tester.pumpAndSettle();
      expect(find.text('اناشيد عامة'), findsOneWidget);
      expect(
          find.text(spec.ar
              ? 'تم تحميل 1 · متبقي أو متوقف 2'
              : '1 downloaded · 2 remaining or stopped'),
          findsOneWidget);
      await capture('history-');
      // Switching tabs keeps the same controller and imported playlist.
      await tester.tap(spec.width >= 860
          ? find.byKey(const ValueKey('nav-0-label'))
          : find.byKey(const ValueKey('nav-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('toggle-theme')));
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(find.byType(NazzelhaScreen))).brightness,
          spec.dark ? Brightness.light : Brightness.dark);
      await tester.tap(find.byKey(const ValueKey('toggle-language')));
      await tester.pumpAndSettle();
      expect(locale.isArabic, !spec.ar);
      expect(playlist.entries.length, 3);
      expect(playlist.folder, 'اناشيد عامة');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('isDarkMode'), !spec.dark);
      expect(prefs.getString('appLocale'), spec.ar ? 'en' : 'ar');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      playlist.dispose();
      queue.dispose();
      theme.dispose();
      locale.dispose();
    });
  }

  testWidgets('button press respects reduced motion', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: PressMotion(
                child:
                    SizedBox(width: 120, height: 60, child: Text('Action'))))));
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('Action')));
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
