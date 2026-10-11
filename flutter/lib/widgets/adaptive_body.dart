import 'package:flutter/material.dart';

/// Wraps content in a centered, width-constrained container for desktop.
/// On narrow screens (mobile), the child fills the full width.
class AdaptiveBody extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  const AdaptiveBody({
    super.key,
    required this.child,
    this.maxWidth = 600,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    Widget body = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
    if (padding != null) {
      body = Padding(padding: padding!, child: body);
    }
    // Edge-to-edge (SystemChrome.edgeToEdge in main.dart) draws the system
    // gesture bar over the Scaffold body on pushed routes. AppBar already
    // consumes the top inset, so only the bottom needs guarding here.
    // Nested SafeAreas are idempotent (inner sees zero padding), so wrapping
    // screens that already use SafeArea does not double-pad.
    return SafeArea(top: false, bottom: true, child: body);
  }
}
