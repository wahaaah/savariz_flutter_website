import 'package:flutter/material.dart';

class PatientPortalTheme {
  const PatientPortalTheme._();

  static const Color primary = Color(0xFF2563EB);
  static const Color primaryHover = Color(0xFF1D4ED8);

  static final ThemeData light = _buildTheme(
    brightness: Brightness.light,
    primary: primary,
    scaffoldBackground: const Color(0xFFF5F7FB),
    surface: Colors.white,
    text: const Color(0xFF172033),
    secondaryText: const Color(0xFF5F6F86),
    border: const Color(0xFFE2E8F0),
  );

  static final ThemeData dark = _buildTheme(
    brightness: Brightness.dark,
    primary: primary,
    scaffoldBackground: const Color(0xFF0B1220),
    surface: const Color(0xFF111B2D),
    text: const Color(0xFFF1F5F9),
    secondaryText: const Color(0xFFA7B4C7),
    border: const Color(0xFF24334A),
  );

  static ThemeData _buildTheme({
    required Brightness brightness,
    required Color primary,
    required Color scaffoldBackground,
    required Color surface,
    required Color text,
    required Color secondaryText,
    required Color border,
  }) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: brightness,
        ).copyWith(
          primary: primary,
          onPrimary: Colors.white,
          surface: surface,
          onSurface: text,
          outline: border,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackground,
      fontFamily: 'Inter',
      hoverColor: brightness == Brightness.light
          ? const Color(0xFFEFF6FF)
          : const Color(0xFF162238),
      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ).copyWith(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.hovered)) return primaryHover;
                return primary;
              }),
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.hovered)) {
                  return primaryHover.withValues(alpha: 0.12);
                }
                return null;
              }),
            ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: BorderSide(color: border),
        ),
      ),
      textTheme: ThemeData(brightness: brightness).textTheme
          .apply(bodyColor: text, displayColor: text),
      extensions: <ThemeExtension<dynamic>>[
        PatientPortalTextColors(secondary: secondaryText),
      ],
    );
  }
}

class PatientPortalTextColors extends ThemeExtension<PatientPortalTextColors> {
  const PatientPortalTextColors({required this.secondary});

  final Color secondary;

  @override
  PatientPortalTextColors copyWith({Color? secondary}) {
    return PatientPortalTextColors(secondary: secondary ?? this.secondary);
  }

  @override
  PatientPortalTextColors lerp(
    covariant ThemeExtension<PatientPortalTextColors>? other,
    double t,
  ) {
    if (other is! PatientPortalTextColors) return this;
    return PatientPortalTextColors(
      secondary: Color.lerp(secondary, other.secondary, t)!,
    );
  }
}
