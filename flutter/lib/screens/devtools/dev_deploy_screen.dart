import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/wallet_service.dart';
import '../../services/network_service.dart';
import '../../widgets/tonal_button.dart';
import '../../widgets/octra_card.dart';
import '../../widgets/adaptive_body.dart';

/// Deploy Contract screen — desktop only.
class DevDeployScreen extends StatefulWidget {
  const DevDeployScreen({super.key});

  @override
  State<DevDeployScreen> createState() => _DevDeployScreenState();
}

class _DevDeployScreenState extends State<DevDeployScreen> {
  final _bytecodeCtrl = TextEditingController();
  final _argsCtrl = TextEditingController();
  final _ouCtrl = TextEditingController(text: '10000');
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;
  String? _txHash;

  @override
  void dispose() {
    _bytecodeCtrl.dispose();
    _argsCtrl.dispose();
    _ouCtrl.dispose();
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
      final hash = await ws.sendDeployTx(
        nodeUrl: ns.activeNodeUrl,
        bytecode: _bytecodeCtrl.text.trim(),
        constructorArgs: _argsCtrl.text.trim(),
        ou: _ouCtrl.text.trim(),
      );
      if (mounted) setState(() => _txHash = hash);
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
      appBar: AppBar(title: const Text('Deploy Contract')),
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
                  child: Row(children: [
                    Icon(Icons.publish_rounded, color: cs.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(
                      'Deploy compiled smart contract bytecode to the Octra network.',
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    )),
                  ]),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _bytecodeCtrl,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Bytecode (hex)',
                    hintText: '0x...',
                    alignLabelWithHint: true,
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter bytecode' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _argsCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Constructor Args (JSON array, optional)',
                    hintText: '["arg1", 123]',
                    alignLabelWithHint: true,
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _ouCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Operation Units (OU)',
                  ),
                  validator: (v) =>
                      (v == null || int.tryParse(v.trim()) == null)
                          ? 'Enter valid OU'
                          : null,
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  _ErrorBanner(message: _error!),
                  const SizedBox(height: 12),
                ],
                if (_txHash != null) ...[
                  _SuccessBanner(
                      message: 'Deploy TX submitted!\nHash: $_txHash'),
                  const SizedBox(height: 12),
                  TonalButton(label: 'Done', onPressed: () => context.pop()),
                ] else
                  TonalButton(
                    label: 'Deploy',
                    icon: Icons.publish_rounded,
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

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: cs.errorContainer, borderRadius: BorderRadius.circular(10)),
      child: Text(message,
          style: TextStyle(color: cs.onErrorContainer, fontSize: 13)),
    );
  }
}

class _SuccessBanner extends StatelessWidget {
  final String message;
  const _SuccessBanner({required this.message});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10)),
      child: Text(message,
          style: const TextStyle(color: Colors.green, fontSize: 13)),
    );
  }
}
