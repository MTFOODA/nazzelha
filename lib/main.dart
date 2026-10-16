import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:logger/logger.dart';
import 'app.dart';
import 'services/python_service.dart';
import 'services/queue_controller.dart';
import 'theme/locale_provider.dart';
import 'theme/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(900, 800),
      minimumSize: Size(600, 500),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      title: 'Nazzelha',
      titleBarStyle: TitleBarStyle.normal,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // Initialize services
  final logger = Logger();
  final pythonService = PythonService(logger: logger);

  // Initialize Python connection on startup
  try {
    await pythonService.initialize();
    logger.i('Python service initialized successfully');
  } catch (e) {
    logger.e('Failed to initialize Python service: $e');
  }

  runApp(
    MultiProvider(
      providers: [
        Provider<Logger>.value(value: logger),
        Provider<PythonService>.value(value: pythonService),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(
          create: (_) => NazzelhaQueueController(
            python: pythonService,
            logger: logger,
          ),
        ),
      ],
      child: const MyApp(),
    ),
  );
}