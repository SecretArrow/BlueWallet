import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/pin_service.dart';

/// Startup splash — checks wallet/PIN state and routes accordingly.
/// Shows a brief spinner, then:
///   • No wallets → /setup
///   • Wallet exists + PIN set → /pin?mode=unlock
///   • Wallet exists + no PIN → /home  (graceful fallback; PIN setup is
///     required during first-run SetupScreen, so this should not happen)
class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  @override
  void initState() {
    super.initState();
    _checkAndNavigate();
  }

  Future<void> _checkAndNavigate() async {
    // Small delay to allow providers to initialise (avoids race with GoRouter).
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('wallet_ids') ?? [];

    if (ids.isEmpty) {
      // First launch — go to setup wizard.
      if (mounted) context.go('/setup');
      return;
    }

    final pinSet = await PinService.isPinSet();
    if (mounted) {
      if (pinSet) {
        context.go('/pin?mode=unlock');
      } else {
        // Wallet exists but no PIN set — force user to create one now.
        context.go('/pin?mode=create');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/logo_app_octopus.png',
              width: 80,
              height: 80,
              errorBuilder: (_, __, ___) => Icon(
                Icons.account_balance_wallet_rounded,
                size: 72,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Octopus Wallet',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 32),
            CircularProgressIndicator(color: cs.primary),
          ],
        ),
      ),
    );
  }
}
