import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/pin_service.dart';
import '../../widgets/tonal_button.dart';

/// Change PIN screen.  Matches ChangePinActivity.
class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({super.key});

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _success = false;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _changePin() async {
    final current = _currentCtrl.text.trim();
    final newPin = _newCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();
    if (current.length != 6 || newPin.length != 6 || confirm.length != 6) {
      setState(() => _error = 'All PINs must be 6 digits');
      return;
    }
    if (newPin != confirm) {
      setState(() => _error = 'New PINs do not match');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final ok = await PinService.verifyPin(current);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _loading = false;
        _error = 'Current PIN is incorrect';
      });
      return;
    }
    await PinService.changePin(newPin);
    if (mounted) {
      setState(() {
        _loading = false;
        _success = true;
      });
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Change PIN')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Update your security PIN',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 24),
            if (_error != null) ...[
              _Banner(message: _error!, isError: true),
              const SizedBox(height: 12),
            ],
            if (_success) ...[
              _Banner(message: 'PIN changed successfully!', isError: false),
              const SizedBox(height: 12),
            ],
            _PinField(label: 'Current PIN', controller: _currentCtrl),
            const SizedBox(height: 16),
            _PinField(label: 'New PIN', controller: _newCtrl),
            const SizedBox(height: 16),
            _PinField(label: 'Confirm New PIN', controller: _confirmCtrl),
            const SizedBox(height: 24),
            TonalButton(
              label: 'Change PIN',
              loading: _loading,
              onPressed: _loading ? null : _changePin,
            ),
          ],
        ),
      ),
    );
  }
}

class _PinField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  const _PinField({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      maxLength: 6,
      obscureText: true,
      style: const TextStyle(fontSize: 24, letterSpacing: 10),
      decoration: InputDecoration(
        labelText: label,
        hintText: '------',
        counterText: '',
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final String message;
  final bool isError;
  const _Banner({required this.message, required this.isError});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            isError ? cs.errorContainer : Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: isError ? cs.onErrorContainer : Colors.green,
        ),
      ),
    );
  }
}
