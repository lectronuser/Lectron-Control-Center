import 'package:flutter/material.dart';

import '../core/models.dart';

abstract final class AppColors {
  static const bg = Color(0xFF0A0A0F);
  static const surface = Color(0xFF13131A);
  static const surface2 = Color(0xFF1C1C26);
  static const hover = Color(0xFF24243A);
  static const rowAlt = Color(0xFF17171F);
  static const border = Color(0x14FFFFFF);
  static const borderStrong = Color(0x29FFFFFF);
  static const text = Color(0xFFF0F0F5);
  static const muted = Color(0xFF8888A0);
  static const off = Color(0xFF555566);
  static const accent = Color(0xFF3B82F6);
  static const ok = Color(0xFF22C55E);
  static const warn = Color(0xFFF59E0B);
  static const err = Color(0xFFEF4444);
}

Color toneColor(Tone tone, [Color fallback = AppColors.text]) => switch (tone) {
  Tone.none => fallback,
  Tone.muted => AppColors.muted,
  Tone.ok => AppColors.ok,
  Tone.warn => AppColors.warn,
  Tone.err => AppColors.err,
  Tone.accent => AppColors.accent,
};

/// Numbers that line up in tables and do not jitter while they update.
const TextStyle monoStyle = TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontWeight: FontWeight.w500);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.accent, brightness: Brightness.dark).copyWith(
    primary: AppColors.accent,
    onPrimary: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.muted,
    surfaceContainerHighest: AppColors.surface2,
    surfaceContainerHigh: AppColors.surface2,
    surfaceContainer: AppColors.surface2,
    surfaceContainerLow: AppColors.surface,
    outline: AppColors.borderStrong,
    outlineVariant: AppColors.border,
    error: AppColors.err,
  );
  final radius = BorderRadius.circular(8);
  OutlineInputBorder inputBorder(Color color) => OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide(color: color),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Roboto',
    scaffoldBackgroundColor: AppColors.bg,
    visualDensity: VisualDensity.compact,
    splashFactory: NoSplash.splashFactory,
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1, thickness: 1),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 13, color: AppColors.text),
      bodySmall: TextStyle(fontSize: 12, color: AppColors.muted),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: AppColors.surface2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      hintStyle: const TextStyle(color: AppColors.off, fontSize: 13),
      border: inputBorder(AppColors.border),
      enabledBorder: inputBorder(AppColors.border),
      disabledBorder: inputBorder(AppColors.border),
      focusedBorder: inputBorder(AppColors.accent),
      errorBorder: inputBorder(AppColors.err),
      focusedErrorBorder: inputBorder(AppColors.err),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: radius),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(fontFamily: 'Roboto', fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        backgroundColor: AppColors.surface2,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: radius),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        textStyle: const TextStyle(fontFamily: 'Roboto', fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderStrong),
      ),
      textStyle: const TextStyle(color: AppColors.text, fontSize: 12),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(AppColors.hover),
      radius: const Radius.circular(4),
      thickness: WidgetStateProperty.all(8),
    ),
    sliderTheme: const SliderThemeData(trackHeight: 5, inactiveTrackColor: AppColors.surface2),
    checkboxTheme: CheckboxThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
  );
}
