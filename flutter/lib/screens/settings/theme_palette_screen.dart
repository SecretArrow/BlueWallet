import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_manager.dart';

/// Theme settings: brightness mode (System / Dark / Light) plus a palette
/// per slot. Matches ThemePaletteActivity.
///
/// - System mode: the palette follows the OS light/dark setting live
///   (ThemeManager listens for brightness changes); both slots are
///   editable below.
/// - Dark / Light: the forced slot's grid is shown.
/// The palette cells keep the original picking UX (tap to apply).
class ThemePaletteScreen extends StatelessWidget {
  const ThemePaletteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tm = context.watch<ThemeManager>();
    final cs = Theme.of(context).colorScheme;
    final darkPalettes = AppPalette.all.where((p) => p.isDark).toList();
    final lightPalettes = AppPalette.all.where((p) => !p.isDark).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Theme')),
      body: SafeArea(
        top: false,
        bottom: true,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text('Mode', style: _sectionStyle(cs)),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode_outlined),
                ),
              ],
              selected: {tm.themeMode},
              onSelectionChanged: (selection) {
                final m = selection.first;
                tm.setMode(
                  m == ThemeMode.dark
                      ? 'dark'
                      : m == ThemeMode.light
                          ? 'light'
                          : 'system',
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              tm.mode == 'system'
                  ? 'Follows the system light/dark setting. Pick the palette '
                      'for each brightness below.'
                  : 'Forced ${tm.mode} appearance.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            if (tm.mode == 'system' || tm.mode == 'dark')
              _PaletteSection(
                title: 'Dark theme palette',
                palettes: darkPalettes,
                selectedId: tm.darkPaletteId,
                onPick: tm.setDarkPalette,
              ),
            if (tm.mode == 'system') const SizedBox(height: 20),
            if (tm.mode == 'system' || tm.mode == 'light')
              _PaletteSection(
                title: 'Light theme palette',
                palettes: lightPalettes,
                selectedId: tm.lightPaletteId,
                onPick: tm.setLightPalette,
              ),
          ],
        ),
      ),
    );
  }

  static TextStyle _sectionStyle(ColorScheme cs) => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: cs.onSurfaceVariant,
      );
}

/// One slot picker: header + grid of palette cells (the original cell
/// design, selection ring included).
class _PaletteSection extends StatelessWidget {
  final String title;
  final List<AppPalette> palettes;
  final String selectedId;
  final Future<void> Function(String id) onPick;

  const _PaletteSection({
    required this.title,
    required this.palettes,
    required this.selectedId,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.6,
          ),
          itemCount: palettes.length,
          itemBuilder: (_, i) {
            final p = palettes[i];
            final isSelected = selectedId == p.id;
            return GestureDetector(
              onTap: () => onPick(p.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected
                        ? p.primary
                        : p.textSecondary.withValues(alpha: 0.2),
                    width: isSelected ? 2 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: p.primary.withValues(alpha: 0.3),
                            blurRadius: 8,
                            spreadRadius: 0,
                          )
                        ]
                      : null,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Color swatches
                          _Swatch(color: p.background),
                          const SizedBox(width: 4),
                          _Swatch(color: p.primary),
                          const SizedBox(width: 4),
                          _Swatch(color: p.accent),
                          const Spacer(),
                          if (isSelected)
                            Icon(Icons.check_circle_rounded,
                                color: p.primary, size: 18),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        p.label,
                        style: TextStyle(
                          color: p.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        p.isDark ? 'Dark' : 'Light',
                        style: TextStyle(
                          color: p.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  const _Swatch({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.15), width: 0.5),
      ),
    );
  }
}
