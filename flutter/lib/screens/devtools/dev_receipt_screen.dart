import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/wallet_service.dart';
import '../../services/network_service.dart';
import '../../widgets/tonal_button.dart';
import '../../widgets/octopus_card.dart';
import '../../widgets/adaptive_body.dart';

/// Transaction Receipt screen — fetch receipt by hash.
class DevReceiptScreen extends StatefulWidget {
  const DevReceiptScreen({super.key});

  @override
  State<DevReceiptScreen> createState() => _DevReceiptScreenState();
}

class _DevReceiptScreenState extends State<DevReceiptScreen> {
  final _hashCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;
  String? _receipt;

  @override
  void dispose() {
    _hashCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _receipt = null;
    });
    try {
      final ws = context.read<WalletService>();
      final ns = context.read<NetworkService>();
      final result =
          await ws.getReceipt(ns.activeNodeUrl, _hashCtrl.text.trim());
      if (mounted) {
        setState(() =>
            _receipt = const JsonEncoder.withIndent('  ').convert(result));
      }
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Transaction Receipt')),
      body: AdaptiveBody(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              OctopusCard(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Icon(Icons.receipt_long_rounded, color: cs.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(
                    'Fetch the full receipt for a confirmed transaction.',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  )),
                ]),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _hashCtrl,
                decoration:
                    const InputDecoration(labelText: 'Transaction Hash'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                onFieldSubmitted: (_) => _submit(),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              if (_error != null) ...[
                _Banner(message: _error!, isError: true),
                const SizedBox(height: 12),
              ],
              if (_receipt != null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Receipt:',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    TextButton.icon(
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _receipt!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Copied'),
                              duration: Duration(seconds: 1)),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(_receipt!,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 11)),
                ),
                const SizedBox(height: 12),
              ],
              TonalButton(
                label: 'Get Receipt',
                icon: Icons.receipt_long_rounded,
                loading: _loading,
                onPressed: _loading ? null : _submit,
              ),
            ]),
          ),
        ),
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
        color: isError ? cs.errorContainer : Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(message,
          style: TextStyle(
            color: isError ? cs.onErrorContainer : Colors.green,
            fontSize: 13,
          )),
    );
  }
}
