import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/biometric_service.dart';
import '../../services/pin_service.dart';

/// Biometric unlock settings screen.
/// Enabling requires: enter correct PIN → biometric confirmation → PIN
/// encrypted and stored in secure storage. Biometric unlock then verifies
/// biometric → decrypts stored PIN → PinService.verifyPin.
class BiometricSettingsScreen extends StatefulWidget {
  const BiometricSettingsScreen({super.key});

  @override
  State<BiometricSettingsScreen> createState() =>
      _BiometricSettingsScreenState();
}

class _BiometricSettingsScreenState extends State<BiometricSettingsScreen> {
  bool _available = false;
  bool _enabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final available = await BiometricService.isAvailable();
    final enabled = await BiometricService.isEnabled();
    if (mounted) {
      setState(() {
        _available = available;
        _enabled = enabled;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(bool value) async {
    if (value) {
      // Prompt for PIN first so we can encrypt it for biometric unlock.
      final pin = await _promptPin();
      if (pin == null) return; // cancelled

      // Verify the PIN is correct
      final valid = await PinService.verifyPin(pin);
      if (!valid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Incorrect PIN')),
          );
        }
        return;
      }

      // Enable biometric: does biometric auth + stores encrypted PIN
      final ok = await BiometricService.enable(pin);
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Biometric authentication failed')),
          );
        }
        return;
      }
      if (mounted) setState(() => _enabled = true);
    } else {
      await BiometricService.disable();
      if (mounted) setState(() => _enabled = false);
    }
  }

  /// Shows a dialog prompting the user to enter their 6-digit PIN.
  Future<String?> _promptPin() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Enter PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter your 6-digit wallet PIN to enable biometric unlock.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: ctrl,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  obscureText: true,
                  autofocus: true,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  style: const TextStyle(fontSize: 24, letterSpacing: 8),
                  decoration: const InputDecoration(
                    hintText: '••••••',
                    counterText: '',
                  ),
                  onSubmitted: (v) {
                    if (v.length == 6) Navigator.pop(ctx, v);
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (ctrl.text.length == 6) Navigator.pop(ctx, ctrl.text);
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
    ctrl.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
          title: const Text('Biometric Unlock'), centerTitle: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                color: cs.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Hardware availability notice
                      if (!_available) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.errorContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  color: cs.onErrorContainer),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Biometric authentication is not available on '
                                  'this device. Enroll a fingerprint or face '
                                  'in your device settings first.',
                                  style: TextStyle(
                                    color: cs.onErrorContainer,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Toggle
                      SwitchListTile(
                        title: const Text(
                          'Enable Biometric Unlock',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          'Use fingerprint or face recognition to unlock the '
                          'wallet instead of entering your PIN each time.',
                        ),
                        value: _enabled,
                        onChanged: _available ? _toggle : null,
                        contentPadding: EdgeInsets.zero,
                        activeColor: cs.primary,
                      ),

                      // Active status banner
                      if (_enabled) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: cs.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.fingerprint_rounded,
                                  color: cs.primary, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Biometric unlock is active. You can still use '
                                  'your PIN if biometric recognition fails.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),
                      // Info note
                      Text(
                        'Biometrics are only used to verify your identity. '
                        'Your private keys are never shared with the system '
                        'biometric service.',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
