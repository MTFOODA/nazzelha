import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/app_motion.dart';
import 'colors.dart';

class AppTheme {
  static ThemeData get lightTheme => _build(Brightness.light);
  static ThemeData get darkTheme => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final bg = dark ? AppColors.bgDark : AppColors.bgLight;
    final surface = dark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final text = dark ? AppColors.textDark : AppColors.textLight;
    final muted =
        dark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final border = dark ? AppColors.borderDark : AppColors.borderLight;
    final scheme = ColorScheme.fromSeed(
            seedColor: AppColors.primaryLight, brightness: brightness)
        .copyWith(
            primary: dark ? const Color(0xFFA8BFFF) : const Color(0xFF2C52CB),
            onPrimary: dark ? const Color(0xFF0B183B) : Colors.white,
            surface: surface,
            onSurface: text,
            onSurfaceVariant: muted,
            outline: border,
            error: dark ? AppColors.errorDark : const Color(0xFFB42332));
    final base = ThemeData(
        useMaterial3: true, brightness: brightness, colorScheme: scheme);
    final textTheme = GoogleFonts.poppinsTextTheme(base.textTheme).apply(
        bodyColor: text,
        displayColor: text,
        fontFamilyFallback: const ['Tajawal']);
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    final buttonStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 52)),
      padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
      shape: WidgetStatePropertyAll(shape),
      animationDuration: const Duration(milliseconds: 160),
      textStyle: WidgetStatePropertyAll(
          textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
    );
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
          backgroundColor: bg,
          foregroundColor: text,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle:
              textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      cardTheme: CardThemeData(
          color: surface,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(color: border))),
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surface,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: scheme.primary, width: 2)),
          hintStyle: textTheme.bodyMedium?.copyWith(color: muted),
          labelStyle: textTheme.bodyMedium?.copyWith(color: muted)),
      filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: buttonStyle.copyWith(
              backgroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.disabled)
                      ? null
                      : scheme.primary),
              foregroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.disabled)
                      ? null
                      : scheme.onPrimary),
              elevation: const WidgetStatePropertyAll(0))),
      outlinedButtonTheme: OutlinedButtonThemeData(style: buttonStyle),
      textButtonTheme: TextButtonThemeData(
          style: buttonStyle.copyWith(
              minimumSize: const WidgetStatePropertyAll(Size(48, 44)))),
      navigationBarTheme: NavigationBarThemeData(
          backgroundColor: surface,
          elevation: 0,
          indicatorColor: scheme.primaryContainer,
          height: 78,
          labelTextStyle: WidgetStatePropertyAll(
              textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600))),
      navigationRailTheme: NavigationRailThemeData(
          backgroundColor: surface,
          indicatorColor: scheme.primaryContainer,
          selectedIconTheme: IconThemeData(color: scheme.primary),
          unselectedIconTheme: IconThemeData(color: muted),
          selectedLabelTextStyle: textTheme.labelLarge
              ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
          unselectedLabelTextStyle:
              textTheme.labelLarge?.copyWith(color: muted)),
      progressIndicatorTheme: ProgressIndicatorThemeData(
          color: scheme.primary,
          linearTrackColor: scheme.primaryContainer,
          linearMinHeight: 7,
          borderRadius: BorderRadius.circular(20)),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: SoftPageTransitions(),
        TargetPlatform.windows: SoftPageTransitions(),
        TargetPlatform.linux: SoftPageTransitions(),
        TargetPlatform.macOS: SoftPageTransitions(),
        TargetPlatform.iOS: SoftPageTransitions(),
        TargetPlatform.fuchsia: SoftPageTransitions(),
      }),
    );
  }
}
