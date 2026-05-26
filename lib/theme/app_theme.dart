// ignore_for_file: avoid_redundant_argument_values
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Design tokens centralizados para MusiLink.
/// Todos los widgets deben leer colores, tipografía y espaciado desde aquí.
abstract final class AppTokens {
  // ── Colores semánticos ─────────────────────────────────────────────────────
  static const spotifyGreen = Color(0xFF1DB954);
  static const spotifyGreenLight = Color(0xFF1ED760);
  static const spotifyGreenDark = Color(0xFF1AA34A);

  /// Color para los ticks de "mensaje leído" — parte del design system.
  static const readReceiptColor = Color(0xFF4FC3F7); // azul claro suave

  // ── Superficies dark ───────────────────────────────────────────────────────
  static const darkBackground = Color(0xFF121212);
  static const darkCard = Color(0xFF181818);
  static const darkSurface2 = Color(0xFF1E1E1E);
  static const darkSurface3 = Color(0xFF282828);
  static const darkDivider = Color(0xFF2A2A2A);

  // ── Opacidades semánticas ──────────────────────────────────────────────────
  static const alphaMedium = 150; // texto secundario
  static const alphaLow = 100; // texto terciario / placeholders
  static const alphaDisabled = 80;

  // ── Espaciado ─────────────────────────────────────────────────────────────
  static const spaceXS = 4.0;
  static const spaceSM = 8.0;
  static const spaceMD = 12.0;
  static const spaceLG = 16.0;
  static const spaceXL = 24.0;
  static const space2XL = 32.0;

  // ── Radios de borde ───────────────────────────────────────────────────────
  static const radiusSM = 8.0;
  static const radiusMD = 12.0;
  static const radiusLG = 16.0;
  static const radiusFull = 999.0;

  // ── Duraciones de animación ────────────────────────────────────────────────
  static const durationFast = Duration(milliseconds: 150);
  static const durationMedium = Duration(milliseconds: 250);
  static const durationSlow = Duration(milliseconds: 350);

  // ── Tamaños mínimos de touch target ───────────────────────────────────────
  static const minTouchTarget = 44.0;
}

class AppTheme {
  AppTheme._();

  // ── Helpers privados ──────────────────────────────────────────────────────

  static TextTheme _buildTextTheme(ColorScheme cs) {
    return TextTheme(
      // Display — para números grandes como score de compatibilidad
      displayLarge: TextStyle(
        fontSize: 57,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
        color: cs.onSurface,
      ),
      displayMedium: TextStyle(
        fontSize: 45,
        fontWeight: FontWeight.w700,
        color: cs.onSurface,
      ),
      displaySmall: TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        color: cs.onSurface,
      ),
      // Headline — títulos de sección
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: cs.onSurface,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
        color: cs.onSurface,
      ),
      headlineSmall: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: cs.onSurface,
      ),
      // Title — nombres, items de lista
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: cs.onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: cs.onSurface,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        color: cs.onSurface,
      ),
      // Body — texto de contenido
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.15,
        color: cs.onSurface,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.25,
        color: cs.onSurface,
        height: 1.5,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.4,
        color: cs.onSurfaceVariant,
        height: 1.4,
      ),
      // Label — botones, chips, metadatos
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: cs.onSurface,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: cs.onSurfaceVariant,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: cs.onSurfaceVariant,
      ),
    );
  }

  static CardThemeData _buildCardTheme(Color cardColor) {
    return CardThemeData(
      color: cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMD),
      ),
      margin: EdgeInsets.zero,
    );
  }

  static NavigationBarThemeData _buildNavBarTheme(ColorScheme cs) {
    return NavigationBarThemeData(
      backgroundColor: cs.surface,
      indicatorColor: cs.primary.withAlpha(40),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return cs.primary.withAlpha(20);
        }
        if (states.contains(WidgetState.hovered)) {
          return cs.primary.withAlpha(12);
        }
        return Colors.transparent;
      }),
      elevation: 0,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final isSelected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          color: isSelected ? cs.primary : cs.onSurfaceVariant,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final isSelected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 24,
          color: isSelected ? cs.primary : cs.onSurfaceVariant,
        );
      }),
    );
  }

  static TabBarThemeData _buildTabBarTheme(ColorScheme cs) {
    return TabBarThemeData(
      labelColor: cs.primary,
      unselectedLabelColor: cs.onSurfaceVariant,
      labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
      indicatorSize: TabBarIndicatorSize.label,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: cs.primary, width: 2.5),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
      ),
      dividerColor: Colors.transparent,
      splashFactory: InkRipple.splashFactory,
    );
  }

  static ChipThemeData _buildChipTheme(ColorScheme cs) {
    return ChipThemeData(
      backgroundColor: cs.surfaceContainerHighest,
      selectedColor: cs.primary.withAlpha(30),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: cs.onSurface,
      ),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusFull),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      showCheckmark: false,
    );
  }

  static ListTileThemeData _buildListTileTheme(ColorScheme cs) {
    return ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceLG,
        vertical: AppTokens.spaceSM,
      ),
      minVerticalPadding: AppTokens.spaceSM,
      iconColor: cs.onSurfaceVariant,
    );
  }

  static ElevatedButtonThemeData _buildElevatedButtonTheme(ColorScheme cs) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: cs.surfaceContainerHighest,
        foregroundColor: cs.onSurface,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusFull),
        ),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        minimumSize: const Size(0, AppTokens.minTouchTarget),
      ),
    );
  }

  static FilledButtonThemeData _buildFilledButtonTheme(ColorScheme cs) {
    return FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 0,
        minimumSize: const Size(double.infinity, AppTokens.minTouchTarget),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusFull),
        ),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }

  static OutlinedButtonThemeData _buildOutlinedButtonTheme(ColorScheme cs) {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: cs.onSurface,
        side: BorderSide(color: cs.outline),
        minimumSize: const Size(double.infinity, AppTokens.minTouchTarget),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusFull),
        ),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }

  static InputDecorationTheme _buildInputDecorationTheme(ColorScheme cs) {
    final radius = BorderRadius.circular(AppTokens.radiusLG);
    final borderColor = cs.outline;

    return InputDecorationTheme(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceLG,
        vertical: AppTokens.spaceMD,
      ),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: cs.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: cs.error, width: 2),
      ),
      labelStyle: TextStyle(color: cs.onSurfaceVariant),
      floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) {
        if (states.contains(WidgetState.error)) {
          return TextStyle(color: cs.error);
        }
        return TextStyle(color: cs.primary);
      }),
      prefixIconColor: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.error)) return cs.error;
        return cs.onSurfaceVariant;
      }),
      suffixIconColor: cs.onSurfaceVariant,
    );
  }

  static PopupMenuThemeData _buildPopupMenuTheme(ColorScheme cs) {
    return PopupMenuThemeData(
      color: cs.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: cs.shadow.withAlpha(60),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMD),
      ),
      textStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: cs.onSurface,
      ),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: cs.onSurface,
        ),
      ),
    );
  }

  static DividerThemeData _buildDividerTheme(ColorScheme cs) {
    return DividerThemeData(
      color: cs.onSurface.withAlpha(25),
      thickness: 1,
      space: 1,
    );
  }

  static AppBarTheme _buildAppBarTheme(ColorScheme cs) {
    return AppBarTheme(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: cs.shadow.withAlpha(40),
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: cs.onSurface,
      ),
    );
  }

  static SnackBarThemeData _buildSnackBarTheme(ColorScheme cs) {
    return SnackBarThemeData(
      backgroundColor: cs.surfaceContainerHigh,
      contentTextStyle: TextStyle(color: cs.onSurface),
      actionTextColor: cs.primary,
      closeIconColor: cs.onSurfaceVariant,
      behavior: SnackBarBehavior.floating,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMD),
      ),
    );
  }

  // ── Temas públicos ────────────────────────────────────────────────────────

  static ThemeData get darkTheme {
    const cs = ColorScheme.dark(
      primary: AppTokens.spotifyGreen,
      onPrimary: Colors.black,
      primaryContainer: Color(0xFF0A3D1F),
      onPrimaryContainer: AppTokens.spotifyGreenLight,
      secondary: AppTokens.spotifyGreenLight,
      onSecondary: Colors.black,
      surface: AppTokens.darkBackground,
      onSurface: Color(0xFFEEEEEE),
      surfaceContainerLowest: Color(0xFF0A0A0A),
      surfaceContainerLow: AppTokens.darkCard,
      surfaceContainer: AppTokens.darkSurface2,
      surfaceContainerHigh: AppTokens.darkSurface3,
      surfaceContainerHighest: AppTokens.darkDivider,
      onSurfaceVariant: Color(0xFFAAAAAA),
      outline: Color(0xFF3A3A3A),
      outlineVariant: Color(0xFF2A2A2A),
      surfaceTint: Colors.transparent,
      error: Color(0xFFCF6679),
      onError: Colors.black,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: Color(0xFFEEEEEE),
      onInverseSurface: Color(0xFF1A1A1A),
      inversePrimary: AppTokens.spotifyGreenDark,
    );

    final textTheme = _buildTextTheme(cs);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: cs,
      textTheme: textTheme,
      cardTheme: _buildCardTheme(AppTokens.darkCard),
      appBarTheme: _buildAppBarTheme(cs),
      navigationBarTheme: _buildNavBarTheme(cs),
      tabBarTheme: _buildTabBarTheme(cs),
      chipTheme: _buildChipTheme(cs),
      listTileTheme: _buildListTileTheme(cs),
      elevatedButtonTheme: _buildElevatedButtonTheme(cs),
      filledButtonTheme: _buildFilledButtonTheme(cs),
      outlinedButtonTheme: _buildOutlinedButtonTheme(cs),
      dividerTheme: _buildDividerTheme(cs),
      inputDecorationTheme: _buildInputDecorationTheme(cs),
      popupMenuTheme: _buildPopupMenuTheme(cs),
      snackBarTheme: _buildSnackBarTheme(cs),
      iconTheme: IconThemeData(color: cs.onSurfaceVariant, size: 24),
      splashFactory: InkRipple.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static ThemeData get lightTheme {
    const cs = ColorScheme.light(
      primary: AppTokens.spotifyGreenDark,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFB7F5CC),
      onPrimaryContainer: Color(0xFF00391A),
      secondary: AppTokens.spotifyGreen,
      onSecondary: Colors.white,
      surface: Colors.white,
      onSurface: Color(0xFF0F0F0F),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Color(0xFFF5F5F5),
      surfaceContainer: Color(0xFFEFEFEF),
      surfaceContainerHigh: Color(0xFFE8E8E8),
      surfaceContainerHighest: Color(0xFFE0E0E0),
      onSurfaceVariant: Color(0xFF555555),
      outline: Color(0xFFCCCCCC),
      outlineVariant: Color(0xFFE5E5E5),
      surfaceTint: Colors.transparent,
      error: Color(0xFFB00020),
      onError: Colors.white,
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFF1A1A1A),
      onInverseSurface: Color(0xFFF0F0F0),
      inversePrimary: AppTokens.spotifyGreenLight,
    );

    final textTheme = _buildTextTheme(cs);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: cs,
      textTheme: textTheme,
      cardTheme: _buildCardTheme(const Color(0xFFF8F8F8)),
      appBarTheme: _buildAppBarTheme(cs),
      navigationBarTheme: _buildNavBarTheme(cs),
      tabBarTheme: _buildTabBarTheme(cs),
      chipTheme: _buildChipTheme(cs),
      listTileTheme: _buildListTileTheme(cs),
      elevatedButtonTheme: _buildElevatedButtonTheme(cs),
      filledButtonTheme: _buildFilledButtonTheme(cs),
      outlinedButtonTheme: _buildOutlinedButtonTheme(cs),
      dividerTheme: _buildDividerTheme(cs),
      inputDecorationTheme: _buildInputDecorationTheme(cs),
      popupMenuTheme: _buildPopupMenuTheme(cs),
      snackBarTheme: _buildSnackBarTheme(cs),
      iconTheme: IconThemeData(color: cs.onSurfaceVariant, size: 24),
      splashFactory: InkRipple.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
