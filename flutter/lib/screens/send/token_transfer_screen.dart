import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/wallet_service.dart';
import '../../services/network_service.dart';
import '../../widgets/tonal_button.dart';
import '../../widgets/octra_card.dart';
import '../../widgets/adaptive_body.dart';

/// Token Transfer screen — send tokens via contract call.
class TokenTransferScreen extends StatefulWidget {
  final String? initialTokenAddress;
  final String? initialTokenSymbol;

  const TokenTransferScreen({
    super.key,
    this.initialTokenAddress,
    this.initialTokenSymbol,
  });

  @override
  State<TokenTransferScreen> createState() => _TokenTransferScreenState();
}

class _TokenTransferScreenState extends State<TokenTransferScreen> {
  final _tokenAddrCtrl = TextEditingController();
  final _recipientCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;
  String? _txHash;
  String? _selectedDropdownToken;

  @override
  void initState() {
    super.initState();
    if (widget.initialTokenAddress != null &&
        widget.initialTokenAddress!.isNotEmpty) {
      _tokenAddrCtrl.text = widget.initialTokenAddress!;
      _selectedDropdownToken = widget.initialTokenAddress;
    }
  }

  @override
  void dispose() {
    _tokenAddrCtrl.dispose();
    _recipientCtrl.dispose();
    _amountCtrl.dispose();
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
      final hash = await ws.sendContractCallTx(
        nodeUrl: ns.activeNodeUrl,
        tokenAddress: _tokenAddrCtrl.text.trim(),
        toAddress: _recipientCtrl.text.trim(),
        amount: _amountCtrl.text.trim(),
      );
      if (mounted) setState(() => _txHash = hash);
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
    final pubBalance = ws.publicBalance;

    return Scaffold(
      appBar: AppBar(title: const Text('Token Transfer')),
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
                      Icon(Icons.token_rounded, color: cs.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Transfer tokens via smart contract call.',
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // OCT public balance for reference
                OctopusCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('OCT Balance',
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 13)),
                      Text('$pubBalance OCT',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Token input — dropdown when tokens are loaded, text field otherwise
                if (ws.tokens.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    value: _selectedDropdownToken,
                    decoration: const InputDecoration(
                      labelText: 'Token',
                    ),
                    hint: const Text('Select token'),
                    isExpanded: true,
                    items: ws.tokens
                        .map((t) => DropdownMenuItem(
                              value: t.address,
                              child: Text('${t.symbol} - ${t.name}'),
                            ))
                        .toList(),
                    validator: (v) => v == null ? 'Select a token' : null,
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _tokenAddrCtrl.text = v;
                          _selectedDropdownToken = v;
                        });
                      }
                    },
                  ),
                ] else ...[
                  TextFormField(
                    controller: _tokenAddrCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Token Contract Address',
                      hintText: 'oct...',
                    ),
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter token address'
                        : null,
                  ),
                ],
                const SizedBox(height: 14),
                TextFormField(
                  controller: _recipientCtrl,
                  decoration: InputDecoration(
                    labelText: 'Recipient Address',
                    hintText: 'oct...',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      onPressed: () async {
                        final r = await context.push<String>('/qr-scan');
                        if (r != null && mounted) {
                          _recipientCtrl.text = r;
                        }
                      },
                    ),
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Enter recipient address'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: false),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    hintText: 'Integer token amount',
                  ),
                  onFieldSubmitted: (_) => _submit(),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Enter amount';
                    if (int.tryParse(v.trim()) == null) {
                      return 'Must be a whole number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  _Banner(message: _error!, isError: true),
                  const SizedBox(height: 12),
                ],
                if (_txHash != null) ...[
                  _Banner(
                      message: 'Token transfer submitted!\nTX: $_txHash',
                      isError: false),
                  const SizedBox(height: 12),
                  TonalButton(label: 'Done', onPressed: () => context.pop()),
                ] else ...[
                  TonalButton(
                    label: 'Transfer Tokens',
                    icon: Icons.token_rounded,
                    loading: _loading,
                    onPressed: _loading ? null : _submit,
                  ),
                ],
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
