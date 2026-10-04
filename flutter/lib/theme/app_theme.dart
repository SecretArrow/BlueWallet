import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';

/// Builds a [ThemeData] from an [AppPalette].
class AppTheme {
  static ThemeData fromPalette(AppPalette p) {
    final brightness = p.isDark ? Brightness.dark : Brightness.light;
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: p.primary,
      onPrimary: p.isDark ? Colors.black : Colors.white,
      primaryContainer: p.primaryContainer,
      onPrimaryContainer: p.onPrimaryContainer,
      secondary: p.accent,
      onSecondary: p.isDark ? Colors.black : Colors.white,
      secondaryContainer: p.accent.withOpacity(0.2),
      onSecondaryContainer: p.accent,
      surface: p.surface,
      onSurface: p.textPrimary,
      surfaceContainerHighest: p.surfaceVariant,
      onSurfaceVariant: p.textSecondary,
      error: p.error,
      onError: Colors.white,
      errorContainer: p.error.withOpacity(0.15),
      onErrorContainer: p.error,
      outline: p.textSecondary.withOpacity(0.4),
      outlineVariant: p.textSecondary.withOpacity(0.2),
      shadow: Colors.black,
      scrim: Colors.black54,
      inverseSurface: p.textPrimary,
      onInverseSurface: p.background,
      inversePrimary: p.primaryDark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: p.background,
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface,
        foregroundColor: p.textPrimary,
        elevation: 0,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: p.isDark ? p.primaryDark : p.surface,
          statusBarBrightness: p.isDark ? Brightness.dark : Brightness.light,
          statusBarIconBrightness:
              p.isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: p.background,
          systemNavigationBarIconBrightness:
              p.isDark ? Brightness.light : Brightness.dark,
        ),
        titleTextStyle: TextStyle(
          color: p.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.primary.withOpacity(0.15),
          foregroundColor: p.primary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: p.isDark ? Colors.black : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.primary,
          side: BorderSide(color: p.primary.withOpacity(0.5)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.textSecondary.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.error),
        ),
        hintStyle: TextStyle(color: p.textSecondary, fontSize: 14),
        labelStyle: TextStyle(color: p.textSecondary),
        floatingLabelStyle: TextStyle(color: p.primary),
      ),
      textTheme: TextTheme(
        displayLarge: TextStyle(
            color: p.textPrimary, fontWeight: FontWeight.bold, fontSize: 32),
        displayMedium: TextStyle(
            color: p.textPrimary, fontWeight: FontWeight.bold, fontSize: 28),
        displaySmall: TextStyle(
            color: p.textPrimary, fontWeight: FontWeight.bold, fontSize: 24),
        headlineMedium: TextStyle(
            color: p.textPrimary, fontWeight: FontWeight.w600, fontSize: 20),
        headlineSmall: TextStyle(
            color: p.textPrimary, fontWeight: FontWeight.w600, fontSize: 18),
        titleLarge: TextStyle(
            color: p.textPrimary, fontWeight: FontWeight.w600, fontSize: 16),
        titleMedium: TextStyle(
            color: p.textPrimary, fontWeight: FontWeight.w500, fontSize: 14),
        titleSmall: TextStyle(
            color: p.textSecondary, fontWeight: FontWeight.w500, fontSize: 13),
        bodyLarge: TextStyle(color: p.textPrimary, fontSize: 15),
        bodyMedium: TextStyle(color: p.textPrimary, fontSize: 14),
        bodySmall: TextStyle(color: p.textSecondary, fontSize: 12),
        labelLarge: TextStyle(
            color: p.primary, fontWeight: FontWeight.w600, fontSize: 14),
        labelSmall: TextStyle(color: p.textSecondary, fontSize: 11),
      ),
      dividerTheme: DividerThemeData(
        color: p.textSecondary.withOpacity(0.12),
        thickness: 1,
        space: 1,
      ),
      iconTheme: IconThemeData(color: p.primary),
      listTileTheme: ListTileThemeData(
        tileColor: p.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        iconColor: p.primary,
        textColor: p.textPrimary,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: p.primary.withOpacity(0.2),
        labelStyle: TextStyle(color: p.textPrimary, fontSize: 12),
        side: BorderSide(color: p.textSecondary.withOpacity(0.2)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surface,
        contentTextStyle: TextStyle(color: p.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.surface,
        selectedItemColor: p.primary,
        unselectedItemColor: p.textSecondary,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        indicatorColor: p.primary.withOpacity(0.15),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: p.primary);
          }
          return IconThemeData(color: p.textSecondary);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
                color: p.primary, fontSize: 12, fontWeight: FontWeight.w600);
          }
          return TextStyle(color: p.textSecondary, fontSize: 12);
        }),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primary,
        foregroundColor: p.isDark ? Colors.black : Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: TextStyle(
            color: p.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
        contentTextStyle: TextStyle(color: p.textSecondary, fontSize: 14),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        modalBackgroundColor: p.surface,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.primary;
          return p.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return p.primary.withOpacity(0.3);
          }
          return p.textSecondary.withOpacity(0.2);
        }),
      ),
      progressIndicatorTheme:
          ProgressIndicatorThemeData(color: p.primary, linearTrackColor: p.primary.withOpacity(0.2)),
    );
  }
}
