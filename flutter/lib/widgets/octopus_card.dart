import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A styled card used throughout the app — matches `MaterialCardView`.
class OctopusCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final VoidCallback? onTap;
  final double borderWidth;
  final Color? borderColor;

  const OctopusCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = 16,
    this.onTap,
    this.borderWidth = 0.5,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveBorder =
        borderColor ?? cs.outlineVariant.withValues(alpha: 0.25);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: borderWidth > 0
            ? Border.all(color: effectiveBorder, width: borderWidth)
            : null,
      ),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A copyable monospace address with icon.
class AddressChip extends StatelessWidget {
  final String address;
  final bool truncate;

  const AddressChip({super.key, required this.address, this.truncate = true});

  String get _display {
    if (!truncate || address.length <= 16) return address;
    return '${address.substring(0, 8)}...${address.substring(address.length - 8)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: address));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Address copied'), duration: Duration(seconds: 2)),
        );
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              _display,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.copy, size: 14, color: cs.primary),
        ],
      ),
    );
  }
}

/// Status badge chip.
class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const StatusBadge({super.key, required this.label, required this.color});

  static StatusBadge forStatus(String status) {
    final c = switch (status) {
      'confirmed' => Colors.green,
      'pending' => Colors.orange,
      'failed' => Colors.red,
      _ => Colors.grey,
    };
    return StatusBadge(label: status.toUpperCase(), color: c);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
