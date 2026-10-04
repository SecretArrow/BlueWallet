import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/wallet_service.dart';
import '../../services/network_service.dart';
import '../../widgets/tonal_button.dart';
import '../../widgets/octra_card.dart';
import '../../widgets/adaptive_body.dart';

/// Encrypt Balance screen — move public balance to encrypted (stealth) balance.
/// Matches EncryptBalanceActivity.
class EncryptBalanceScreen extends StatefulWidget {
  const EncryptBalanceScreen({super.key});

  @override
  State<EncryptBalanceScreen> createState() => _EncryptBalanceScreenState();
}

class _EncryptBalanceScreenState extends State<EncryptBalanceScreen> {
  final _amtCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;
  // final _txHash is removed as we navigate away on success

  @override
  void dispose() {
    _amtCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ws = context.read<WalletService>();
      final ns = context.read<NetworkService>();
      final hash = await ws.sendEncryptTx(
        nodeUrl: ns.activeNodeUrl,
        amount: WalletService.parseOct(_amtCtrl.text.trim()),
      );
      if (mounted) {
        context.go('/tx-progress', extra: {
          'txHash': hash,
          'amount': _amtCtrl.text.trim(),
          'opType': 'encrypt',
        });
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
    final ws = context.watch<WalletService>();
    // Use publicBalance string from WalletService
    final pubBalance = ws.publicBalance;

    return Scaffold(
      appBar: AppBar(title: const Text('Encrypt Balance')),
      body: AdaptiveBody(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OctopusCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.lock_rounded, color: cs.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Move OCT from public balance to encrypted (stealth) balance.',
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                OctopusCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Available',
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 13)),
                      Text('$pubBalance OCT',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _amtCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount to Encrypt',
                    suffixText: 'OCT',
                    suffixIcon: TextButton(
                      onPressed: () => _amtCtrl.text = ws.publicBalance,
                      child: const Text('MAX'),
                    ),
                  ),
                  onFieldSubmitted: (_) => _submit(),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Enter amount';
                    if (double.tryParse(v.trim()) == null)
                      return 'Invalid amount';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  _Banner(message: _error!, isError: true),
                  const SizedBox(height: 12),
                ],
                TonalButton(
                  label: 'Encrypt Balance',
                  icon: Icons.lock_rounded,
                  loading: _loading,
                  onPressed: _loading ? null : _submit,
                ),
              ],
            ),
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
      child: Text(
        message,
        style: TextStyle(
          color: isError ? cs.onErrorContainer : Colors.green,
          fontSize: 13,
        ),
      ),
    );
  }
}
