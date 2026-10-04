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
    return body;
  }
}
