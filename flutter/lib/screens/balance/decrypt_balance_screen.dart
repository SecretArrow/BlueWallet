import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/wallet_service.dart';
import '../../services/network_service.dart';
import '../../services/crypto_service.dart';
import '../../widgets/tonal_button.dart';
import '../../widgets/octra_card.dart';
import '../../widgets/adaptive_body.dart';

/// Decrypt Balance screen — move encrypted balance back to public balance.
/// Matches DecryptBalanceActivity.
class DecryptBalanceScreen extends StatefulWidget {
  const DecryptBalanceScreen({super.key});

  @override
  State<DecryptBalanceScreen> createState() => _DecryptBalanceScreenState();
}

class _DecryptBalanceScreenState extends State<DecryptBalanceScreen> {
  final _amtCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;
  // final _txHash is removed as we navigate away on success
  bool _pvacNotAvailable = false;

  @override
  void initState() {
    super.initState();
    // Check PVAC availability on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!CryptoService.pvacAvailable) {
        setState(() {
          _pvacNotAvailable = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _amtCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Double-check PVAC availability
    if (_pvacNotAvailable) {
      setState(() {
        _error =
            'PVAC (FHE) is not available on this device. This feature requires arm64 or x86_64 architecture.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ws = context.read<WalletService>();

      // Ensure PVAC is initialized
      if (!ws.pvacInitialised) {
        await ws.initPvac();
      }

      if (!CryptoService.pvacAvailable) {
        throw Exception('PVAC not available on this device');
      }

      if (!mounted) return;
      final ns = context.read<NetworkService>();
      final hash = await ws.sendDecryptTx(
        nodeUrl: ns.activeNodeUrl,
        amount: WalletService.parseOct(_amtCtrl.text.trim()),
      );
      if (mounted) {
        context.go('/tx-progress', extra: {
          'txHash': hash,
          'amount': _amtCtrl.text.trim(),
          'opType': 'decrypt',
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ws = context.watch<WalletService>();
    final encBalance = ws.encryptedBalance;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Decrypt Balance')),
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
                      Icon(Icons.lock_open_rounded,
                          color: cs.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Move OCT from encrypted (stealth) balance back to public balance.',
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // PVAC availability warning
                if (_pvacNotAvailable) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_rounded,
                            color: cs.onErrorContainer, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'PVAC (FHE) not available on this device. Encrypted balance cannot be decrypted.',
                            style: TextStyle(
                                color: cs.onErrorContainer, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // Available encrypted balance
                OctopusCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Encrypted Balance',
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 13)),
                      Text('$encBalance OCT',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                if (ws.encryptedBalanceRaw > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Raw: ${ws.encryptedBalanceRaw} micro-OCT',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 14),
                TextFormField(
                  controller: _amtCtrl,
                  enabled: !_pvacNotAvailable,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount to Decrypt',
                    suffixText: 'OCT',
                    suffixIcon: TextButton(
                      onPressed: !_pvacNotAvailable
                          ? () => _amtCtrl.text =
                              context.read<WalletService>().encryptedBalance
                          : null,
                      child: const Text('MAX'),
                    ),
                  ),
                  onFieldSubmitted: (_) => _submit(),
                  validator: (v) {
                    if (_pvacNotAvailable) return 'PVAC not available';
                    if (v == null || v.trim().isEmpty) return 'Enter amount';
                    if (double.tryParse(v.trim()) == null) {
                      return 'Invalid amount';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  _Banner(message: _error!, isError: true),
                  const SizedBox(height: 12),
                ],
                TonalButton(
                  label: 'Decrypt Balance',
                  icon: Icons.lock_open_rounded,
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
        color:
            isError ? cs.errorContainer : Colors.green.withValues(alpha: 0.1),
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
