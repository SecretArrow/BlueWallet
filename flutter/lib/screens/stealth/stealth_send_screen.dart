import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/wallet_service.dart';
import '../../services/network_service.dart';
import '../../widgets/tonal_button.dart';
import '../../widgets/octopus_card.dart';
import '../../widgets/adaptive_body.dart';

/// Stealth Send screen.  Matches StealthSendActivity.
class StealthSendScreen extends StatefulWidget {
  const StealthSendScreen({super.key});

  @override
  State<StealthSendScreen> createState() => _StealthSendScreenState();
}

class _StealthSendScreenState extends State<StealthSendScreen> {
  final _stealthAddrCtrl = TextEditingController();
  final _amtCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;
  // final _txHash is removed as we navigate away on success

  @override
  void dispose() {
    _stealthAddrCtrl.dispose();
    _amtCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ws = context.read<WalletService>();
      final ns = context.read<NetworkService>();
      final hash = await ws.sendStealthTx(
        nodeUrl: ns.activeNodeUrl,
        toAddress: _stealthAddrCtrl.text.trim(),
        amount: WalletService.parseOct(_amtCtrl.text.trim()),
      );
      if (mounted) {
        context.go('/tx-progress', extra: {
          'txHash': hash,
          'amount': _amtCtrl.text.trim(),
          'toAddress': _stealthAddrCtrl.text.trim(),
          'opType': 'stealth',
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
    final encBalance = ws.encryptedBalance;
    final pubBalance = ws.publicBalance;

    return Scaffold(
      appBar: AppBar(title: const Text('Stealth Send')),
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
                      Icon(Icons.visibility_off_rounded,
                          color: cs.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Stealth transactions use one-time addresses for enhanced privacy.',
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Available balances
                OctopusCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Encrypted Balance',
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 13)),
                          Text('$encBalance OCT',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Public Balance',
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 13)),
                          Text('$pubBalance OCT',
                              style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _stealthAddrCtrl,
                  decoration: InputDecoration(
                    labelText: 'Stealth Address',
                    hintText: 'oct...',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      onPressed: () async {
                        final r = await context.push<String>('/qr-scan');
                        if (r != null && mounted) _stealthAddrCtrl.text = r;
                      },
                    ),
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Enter stealth address'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _amtCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    suffixText: 'OCT',
                  ),
                  onFieldSubmitted: (_) => _send(),
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
                  label: 'Send Stealth',
                  icon: Icons.visibility_off_rounded,
                  loading: _loading,
                  onPressed: _loading ? null : _send,
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
