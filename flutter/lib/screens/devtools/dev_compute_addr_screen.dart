import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/wallet_service.dart';
import '../../services/network_service.dart';
import '../../widgets/tonal_button.dart';
import '../../widgets/octra_card.dart';
import '../../widgets/adaptive_body.dart';

/// Compute Contract Address screen — predict address from deployer + nonce.
class DevComputeAddrScreen extends StatefulWidget {
  const DevComputeAddrScreen({super.key});

  @override
  State<DevComputeAddrScreen> createState() => _DevComputeAddrScreenState();
}

class _DevComputeAddrScreenState extends State<DevComputeAddrScreen> {
  final _deployerCtrl = TextEditingController();
  final _nonceCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;
  String? _address;

  @override
  void initState() {
    super.initState();
    // Pre-fill deployer with active wallet address
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ws = context.read<WalletService>();
      _deployerCtrl.text = ws.activeWallet?.address ?? '';
    });
  }

  @override
  void dispose() {
    _deployerCtrl.dispose();
    _nonceCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _address = null;
    });
    try {
      final ws = context.read<WalletService>();
      final ns = context.read<NetworkService>();
      final addr = await ws.computeContractAddress(
        ns.activeNodeUrl,
        _deployerCtrl.text.trim(),
        int.parse(_nonceCtrl.text.trim()),
      );
      if (mounted) setState(() => _address = addr);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Compute Address')),
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
                  Icon(Icons.calculate_rounded, color: cs.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(
                    'Predict the contract address that will be created by a deploy transaction.',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  )),
                ]),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _deployerCtrl,
                decoration: const InputDecoration(
                    labelText: 'Deployer Address', hintText: 'oct...'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nonceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Nonce'),
                onFieldSubmitted: (_) => _submit(),
                validator: (v) => (v == null || int.tryParse(v.trim()) == null)
                    ? 'Enter valid nonce'
                    : null,
              ),
              const SizedBox(height: 16),
              if (_error != null) ...[
                _Banner(message: _error!, isError: true),
                const SizedBox(height: 12),
              ],
              if (_address != null) ...[
                const Text('Predicted Address:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    Expanded(
                        child: SelectableText(_address!,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 13))),
                    IconButton(
                      icon:
                          Icon(Icons.copy_rounded, size: 16, color: cs.primary),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _address!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Copied'),
                              duration: Duration(seconds: 1)),
                        );
                      },
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
              ],
              TonalButton(
                label: 'Compute',
                icon: Icons.calculate_rounded,
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
        color:
            isError ? cs.errorContainer : Colors.green.withValues(alpha: 0.1),
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
