import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/wallet_service.dart';
import '../../services/network_service.dart';
import '../../services/address_book_service.dart';
import '../../widgets/tonal_button.dart';
import '../../widgets/octra_card.dart';
import '../../widgets/adaptive_body.dart';

/// Standard send screen — matches SendActivity.
class SendScreen extends StatefulWidget {
  final String? prefillAddress;

  const SendScreen({super.key, this.prefillAddress});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final _toCtrl = TextEditingController();
  final _amtCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  String? _error;
  String? _txHash;

  @override
  void initState() {
    super.initState();
    if (widget.prefillAddress != null) {
      _toCtrl.text = widget.prefillAddress!;
    }
  }

  @override
  void dispose() {
    _toCtrl.dispose();
    _amtCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _txHash = null;
    });
    try {
      final ws = context.read<WalletService>();
      final ns = context.read<NetworkService>();
      final hash = await ws.sendTransaction(
        nodeUrl: ns.activeNodeUrl,
        toAddress: _toCtrl.text.trim(),
        amount: _amtCtrl.text.trim(),
        memo: _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
      );
      // Auto-refresh balance in background (silent, no loading indicator)
      ws
          .refresh(ns.activeNodeUrl)
          .catchError((_) => null); // Ignore errors silently
      if (mounted) {
        context.go('/tx-progress', extra: {
          'txHash': hash,
          'amount': _amtCtrl.text.trim(),
          'toAddress': _toCtrl.text.trim(),
          'opType': 'standard',
        });
      }
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
    if (mounted) setState(() => _loading = false);
  }

  void _pickFromAddressBook() {
    final entries = context.read<AddressBookService>().entries;
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Address book is empty')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Address Book',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          ...entries.map((e) => ListTile(
                title: Text(e.label),
                subtitle: Text(
                  e.address,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                onTap: () {
                  _toCtrl.text = e.address;
                  Navigator.pop(ctx);
                },
              )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ws = context.watch<WalletService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Send')),
      body: AdaptiveBody(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // From wallet info
                OctopusCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.account_balance_wallet_outlined,
                          size: 20, color: cs.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(ws.activeWallet?.name ?? 'No wallet',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13)),
                            Text(
                              'Balance: ${ws.publicBalance}',
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // To address
                TextFormField(
                  controller: _toCtrl,
                  decoration: InputDecoration(
                    labelText: 'Recipient Address',
                    hintText: 'oct...',
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.qr_code_scanner_rounded),
                          onPressed: () async {
                            final result =
                                await context.push<String>('/qr-scan');
                            if (result != null && mounted) {
                              _toCtrl.text = result;
                            }
                          },
                          tooltip: 'Scan QR',
                        ),
                        IconButton(
                          icon: const Icon(Icons.contact_page_outlined),
                          onPressed: _pickFromAddressBook,
                          tooltip: 'Address Book',
                        ),
                      ],
                    ),
                    prefixStyle: const TextStyle(fontFamily: 'monospace'),
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Enter recipient address'
                      : null,
                ),
                const SizedBox(height: 16),

                // Amount
                TextFormField(
                  controller: _amtCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    hintText: '0.00000000',
                    suffixText: 'OCT',
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Enter amount';
                    if (double.tryParse(v.trim()) == null)
                      return 'Invalid amount';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Memo (optional)
                TextFormField(
                  controller: _memoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Memo (optional)',
                    hintText: 'Add a note...',
                  ),
                  maxLength: 128,
                  maxLines: 2,
                  onFieldSubmitted: (_) => _send(),
                ),
                const SizedBox(height: 8),

                // Error
                if (_error != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_error!,
                        style: TextStyle(color: cs.onErrorContainer)),
                  ),
                  const SizedBox(height: 12),
                ],

                // Success
                if (_txHash != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Transaction submitted!',
                            style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          'TX Hash: $_txHash',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TonalButton(
                    label: 'Done',
                    onPressed: () => context.pop(),
                  ),
                  const SizedBox(height: 8),
                ],

                if (_txHash == null)
                  TonalButton(
                    label: 'Send',
                    icon: Icons.send_rounded,
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
