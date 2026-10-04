import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/tonal_button.dart';
import '../../widgets/octopus_card.dart';

/// Generic Confirm Action screen.
/// Accepts a Map<String, dynamic> via router `extra`:
///   - title    (String) — modal title
///   - message  (String) — body text
///   - confirm  (String) — confirm button label  (default: 'Confirm')
///   - cancel   (String) — cancel button label   (default: 'Cancel')
///   - danger   (bool)   — show confirm button in error color
///
/// Returns `true` (confirmed) or `false`/null (cancelled) via context.pop().
class ConfirmActionScreen extends StatelessWidget {
  final Map<String, dynamic>? data;
  const ConfirmActionScreen({super.key, this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final title = (data?['title'] as String?) ?? 'Confirm';
    final message = (data?['message'] as String?) ?? 'Are you sure?';
    final confirmLabel = (data?['confirm'] as String?) ?? 'Confirm';
    final cancelLabel = (data?['cancel'] as String?) ?? 'Cancel';
    final danger = (data?['danger'] as bool?) ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OctopusCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(
                      danger
                          ? Icons.warning_amber_rounded
                          : Icons.help_outline_rounded,
                      size: 48,
                      color: danger ? cs.error : cs.primary,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      message,
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              TonalButton(
                label: confirmLabel,
                icon:
                    danger ? Icons.warning_amber_rounded : Icons.check_rounded,
                backgroundColor: danger ? cs.errorContainer : null,
                foregroundColor: danger ? cs.onErrorContainer : null,
                onPressed: () => context.pop(true),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => context.pop(false),
                child: Text(cancelLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
