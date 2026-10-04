import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_manager.dart';

/// Theme palette picker.  Matches ThemePaletteActivity.
class ThemePaletteScreen extends StatelessWidget {
  const ThemePaletteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tm = context.watch<ThemeManager>();

    return Scaffold(
      appBar: AppBar(title: const Text('Theme')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.6,
        ),
        itemCount: AppPalette.all.length,
        itemBuilder: (_, i) {
          final p = AppPalette.all[i];
          final isSelected = tm.paletteId == p.id;
          return GestureDetector(
            onTap: () => tm.setPalette(p.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? p.primary : p.textSecondary.withOpacity(0.2),
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: p.primary.withOpacity(0.3),
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
        border: Border.all(color: Colors.white.withOpacity(0.15), width: 0.5),
      ),
    );
  }
}
