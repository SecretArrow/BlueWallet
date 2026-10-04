import 'package:flutter/material.dart';

/// App palette definitions — matches all Android theme variants.
class AppPalette {
  final String id;
  final String label;
  final Color primary;
  final Color primaryDark;
  final Color accent;
  final Color background;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;
  final Color error;
  final bool isDark;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color surfaceVariant;

  const AppPalette({
    required this.id,
    required this.label,
    required this.primary,
    required this.primaryDark,
    required this.accent,
    required this.background,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.error,
    required this.isDark,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.surfaceVariant,
  });

  static const String _globalError = '#e94560';

  static const List<AppPalette> all = [
    // Zenith (default dark)
    AppPalette(
      id: 'zenith',
      label: 'Zenith',
      primary: Color(0xFF64FFDA),
      primaryDark: Color(0xFF0F3460),
      accent: Color(0xFF64FFDA),
      background: Color(0xFF1A1A2E),
      surface: Color(0xFF16213E),
      textPrimary: Color(0xFFFFFFFF),
      textSecondary: Color(0xFF8892B0),
      error: Color(0xFFE94560),
      isDark: true,
      primaryContainer: Color(0xFF122B25),
      onPrimaryContainer: Color(0xFF64FFDA),
      surfaceVariant: Color(0xFF1E2A48),
    ),
    // Moonbloom
    AppPalette(
      id: 'moonbloom',
      label: 'Moonbloom',
      primary: Color(0xFFBD93F9),
      primaryDark: Color(0xFF6C5B7B),
      accent: Color(0xFFFF79C6),
      background: Color(0xFF282A36),
      surface: Color(0xFF343746),
      textPrimary: Color(0xFFF8F8F2),
      textSecondary: Color(0xFFB9BBD1),
      error: Color(0xFFE94560),
      isDark: true,
      primaryContainer: Color(0xFF29183F),
      onPrimaryContainer: Color(0xFFE9DEFF),
      surfaceVariant: Color(0xFF3E4252),
    ),
    // Frostline (light)
    AppPalette(
      id: 'frostline',
      label: 'Frostline',
      primary: Color(0xFF5E81AC),
      primaryDark: Color(0xFF4C6D95),
      accent: Color(0xFF88C0D0),
      background: Color(0xFFECEFF4),
      surface: Color(0xFFE5E9F0),
      textPrimary: Color(0xFF2E3440),
      textSecondary: Color(0xFF4C566A),
      error: Color(0xFFBF616A),
      isDark: false,
      primaryContainer: Color(0xFFBBCEE0),
      onPrimaryContainer: Color(0xFF1E3A5A),
      surfaceVariant: Color(0xFFD8DEE9),
    ),
    // Signal
    AppPalette(
      id: 'signal',
      label: 'Signal',
      primary: Color(0xFF4F8CFF),
      primaryDark: Color(0xFF3B6FD1),
      accent: Color(0xFFFFB454),
      background: Color(0xFF1E2430),
      surface: Color(0xFF252D3D),
      textPrimary: Color(0xFFE6EDF7),
      textSecondary: Color(0xFFA7B4C8),
      error: Color(0xFFE94560),
      isDark: true,
      primaryContainer: Color(0xFF0C1A33),
      onPrimaryContainer: Color(0xFFC5D8FF),
      surfaceVariant: Color(0xFF2F3749),
    ),
    // Night Pulse
    AppPalette(
      id: 'nightpulse',
      label: 'Night Pulse',
      primary: Color(0xFF8B5CF6),
      primaryDark: Color(0xFF5B21B6),
      accent: Color(0xFF22D3EE),
      background: Color(0xFF0F1021),
      surface: Color(0xFF1B1C3A),
      textPrimary: Color(0xFFF5F7FF),
      textSecondary: Color(0xFFB4B8D3),
      error: Color(0xFFE94560),
      isDark: true,
      primaryContainer: Color(0xFF1C0F40),
      onPrimaryContainer: Color(0xFFDDD0FF),
      surfaceVariant: Color(0xFF272950),
    ),
    // Obsidian Grid
    AppPalette(
      id: 'obsidiangrid',
      label: 'Obsidian Grid',
      primary: Color(0xFF10B981),
      primaryDark: Color(0xFF047857),
      accent: Color(0xFFF59E0B),
      background: Color(0xFF0B0D12),
      surface: Color(0xFF151922),
      textPrimary: Color(0xFFEDF2F7),
      textSecondary: Color(0xFF9AA4B2),
      error: Color(0xFFE94560),
      isDark: true,
      primaryContainer: Color(0xFF052E1C),
      onPrimaryContainer: Color(0xFFB7F5DC),
      surfaceVariant: Color(0xFF1E242F),
    ),
    // Neon Forge
    AppPalette(
      id: 'neonforge',
      label: 'Neon Forge',
      primary: Color(0xFFFF5F56),
      primaryDark: Color(0xFFD94841),
      accent: Color(0xFF27C93F),
      background: Color(0xFF121212),
      surface: Color(0xFF202020),
      textPrimary: Color(0xFFF2F2F2),
      textSecondary: Color(0xFFB8B8B8),
      error: Color(0xFFFF5F56),
      isDark: true,
      primaryContainer: Color(0xFF3A0E0C),
      onPrimaryContainer: Color(0xFFFFCECC),
      surfaceVariant: Color(0xFF2C2C2C),
    ),
    // Ivory Circuit (light)
    AppPalette(
      id: 'ivorycircuit',
      label: 'Ivory Circuit',
      primary: Color(0xFF2563EB),
      primaryDark: Color(0xFF1D4ED8),
      accent: Color(0xFF0EA5E9),
      background: Color(0xFFFFFEFB),
      surface: Color(0xFFF7F9FF),
      textPrimary: Color(0xFF1E293B),
      textSecondary: Color(0xFF5B6474),
      error: Color(0xFFDC2626),
      isDark: false,
      primaryContainer: Color(0xFFDBEAFE),
      onPrimaryContainer: Color(0xFF1E3A8A),
      surfaceVariant: Color(0xFFE2E8F0),
    ),
    // Solar Paper (light)
    AppPalette(
      id: 'solarpaper',
      label: 'Solar Paper',
      primary: Color(0xFFC2410C),
      primaryDark: Color(0xFF9A3412),
      accent: Color(0xFFD97706),
      background: Color(0xFFFFF9ED),
      surface: Color(0xFFFFF3D6),
      textPrimary: Color(0xFF3F2A1D),
      textSecondary: Color(0xFF73553F),
      error: Color(0xFFDC2626),
      isDark: false,
      primaryContainer: Color(0xFFFFEDD5),
      onPrimaryContainer: Color(0xFF7C2D12),
      surfaceVariant: Color(0xFFEEDFCA),
    ),
    // Mist Terminal (light)
    AppPalette(
      id: 'mistterminal',
      label: 'Mist Terminal',
      primary: Color(0xFF0F766E),
      primaryDark: Color(0xFF115E59),
      accent: Color(0xFF14B8A6),
      background: Color(0xFFF1F5F9),
      surface: Color(0xFFE8EEF3),
      textPrimary: Color(0xFF0F172A),
      textSecondary: Color(0xFF475569),
      error: Color(0xFFDC2626),
      isDark: false,
      primaryContainer: Color(0xFF99F6E4),
      onPrimaryContainer: Color(0xFF134E4A),
      surfaceVariant: Color(0xFFCDD7E1),
    ),
    // Light
    AppPalette(
      id: 'light',
      label: 'Light',
      primary: Color(0xFF3A86FF),
      primaryDark: Color(0xFF1D4ED8),
      accent: Color(0xFF3A86FF),
      background: Color(0xFFF8FAFC),
      surface: Color(0xFFFFFFFF),
      textPrimary: Color(0xFF0F172A),
      textSecondary: Color(0xFF475569),
      error: Color(0xFFDC2626),
      isDark: false,
      primaryContainer: Color(0xFFDBEAFE),
      onPrimaryContainer: Color(0xFF1E3A8A),
      surfaceVariant: Color(0xFFE2E8F0),
    ),
    // Pastel
    AppPalette(
      id: 'pastel',
      label: 'Pastel',
      primary: Color(0xFFA1C6EA),
      primaryDark: Color(0xFF6B8FCE),
      accent: Color(0xFFFFB6B9),
      background: Color(0xFFFFF6E9),
      surface: Color(0xFFFAE3D9),
      textPrimary: Color(0xFF4A4E69),
      textSecondary: Color(0xFF6D6875),
      error: Color(0xFFDC2626),
      isDark: false,
      primaryContainer: Color(0xFFD8E8F6),
      onPrimaryContainer: Color(0xFF2D4A6A),
      surfaceVariant: Color(0xFFF0D9CF),
    ),
  ];

  static AppPalette byId(String id) {
    return all.firstWhere((p) => p.id == id, orElse: () => all.first);
  }
}
