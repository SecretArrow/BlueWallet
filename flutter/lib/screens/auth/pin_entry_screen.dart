import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../services/pin_service.dart';
import '../../services/biometric_service.dart';

/// PIN authentication screen.
/// mode='unlock' : verify existing PIN to enter the app.
///                 If biometric unlock is enabled, auto-prompts biometric.
/// mode='create' : set a new PIN (used when wallet exists but no PIN yet).
class PinEntryScreen extends StatefulWidget {
  final String mode;

  const PinEntryScreen({super.key, required this.mode});

  @override
  State<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<PinEntryScreen> {
  final _pinCtrl = TextEditingController();
  final _pin2Ctrl = TextEditingController(); // only used in create mode
  bool _loading = false;
  String? _error;
  int _attempts = 0;
  static const _maxAttempts = 5;

  bool _biometricAvailable = false;
  bool _biometricEnabled = false;

  bool get _isCreate => widget.mode == 'create';

  @override
  void initState() {
    super.initState();
    if (!_isCreate) _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final available = await BiometricService.isAvailable();
    final enabled = await BiometricService.isEnabled();
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _biometricEnabled = enabled;
      });
      // Auto-trigger biometric prompt on unlock mode if enabled.
      if (widget.mode == 'unlock' && available && enabled) {
        _tryBiometric();
      }
    }
  }

  Future<void> _tryBiometric() async {
    // Biometric auth → retrieve stored encrypted PIN → verify PIN → unlock
    final pin = await BiometricService.authenticateAndGetPin(
      reason: 'Unlock Octopus Wallet',
    );
    if (!mounted) return;
    if (pin != null) {
      final ok = await PinService.verifyPin(pin);
      if (!mounted) return;
      if (ok) {
        context.go('/home');
        return;
      }
    }
    setState(() => _error = 'Biometric failed — enter your PIN below.');
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _pin2Ctrl.dispose();
    super.dispose();
  }

  // ── Unlock mode ──────────────────────────────────────────────────────────

  Future<void> _submitUnlock() async {
    final pin = _pinCtrl.text.trim();
    if (pin.length != 6) {
      setState(() => _error = 'Enter a 6-digit PIN');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final ok = await PinService.verifyPin(pin);
    if (!mounted) return;
    setState(() => _loading = false);
    if (ok) {
      context.go('/home');
    } else {
      _attempts++;
      setState(() {
        _pinCtrl.clear();
        _error = _attempts >= _maxAttempts
            ? 'Too many failed attempts. Reset your wallet to continue.'
            : 'Incorrect PIN (${_maxAttempts - _attempts} attempt(s) left)';
      });
    }
  }

  // ── Create mode ──────────────────────────────────────────────────────────

  Future<void> _submitCreate() async {
    final pin1 = _pinCtrl.text.trim();
    final pin2 = _pin2Ctrl.text.trim();
    if (pin1.length != 6) {
      setState(() => _error = 'PIN must be exactly 6 digits');
      return;
    }
    if (pin1 != pin2) {
      setState(() => _error = 'PINs do not match');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    await PinService.setPin(pin1);
    if (mounted) context.go('/home');
  }

  Future<void> _submit() => _isCreate ? _submitCreate() : _submitUnlock();

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showBiometric =
        _biometricAvailable && _biometricEnabled && widget.mode == 'unlock';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 0,
              color: cs.surface,
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title
                    Text(
                      _isCreate ? 'Create Wallet PIN' : 'PIN Required',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isCreate
                          ? 'Set a 6-digit PIN to secure your wallet.'
                          : showBiometric
                              ? 'Use biometric or enter your 6-digit PIN.'
                              : 'Enter your 6-digit wallet PIN to continue.',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),

                    // Error banner
                    if (_error != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: cs.onErrorContainer, fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Biometric button (unlock only)
                    if (showBiometric) ...[
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _tryBiometric,
                          icon: const Icon(Icons.fingerprint_rounded, size: 22),
                          label: const Text('Use Biometric'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: cs.primary),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: Divider(color: cs.outlineVariant)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text('or',
                                style: TextStyle(
                                    color: cs.onSurfaceVariant, fontSize: 12)),
                          ),
                          Expanded(child: Divider(color: cs.outlineVariant)),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

                    // PIN field
                    SizedBox(
                      width: 200,
                      child: TextField(
                        controller: _pinCtrl,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        obscureText: true,
                        autofocus: !showBiometric,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        style: const TextStyle(
                          fontSize: 24,
                          letterSpacing: 8,
                        ),
                        decoration: InputDecoration(
                          hintText: '••••••',
                          counterText: '',
                          labelText: _isCreate ? 'Enter PIN' : null,
                        ),
                        onSubmitted: _isCreate ? null : (_) => _submit(),
                      ),
                    ),

                    // Confirm PIN field (create mode only)
                    if (_isCreate) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: 200,
                        child: TextField(
                          controller: _pin2Ctrl,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          obscureText: true,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          style: const TextStyle(
                            fontSize: 24,
                            letterSpacing: 8,
                          ),
                          decoration: const InputDecoration(
                            hintText: '••••••',
                            counterText: '',
                            labelText: 'Confirm PIN',
                          ),
                          onSubmitted: (_) => _submit(),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Action button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: (_attempts >= _maxAttempts || _loading)
                            ? null
                            : _submit,
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(_isCreate ? 'Set PIN' : 'Unlock'),
                      ),
                    ),
                    if (widget.mode == 'unlock') ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => context.go('/setup'),
                        child: const Text('Reset Wallet'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
