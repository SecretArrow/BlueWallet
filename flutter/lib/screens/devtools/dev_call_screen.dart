import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../services/wallet_service.dart';
import '../../services/network_service.dart';
import '../../widgets/tonal_button.dart';
import '../../widgets/octra_card.dart';
import '../../widgets/adaptive_body.dart';

/// Call Contract screen — execute a state-changing contract function.
class DevCallScreen extends StatefulWidget {
  const DevCallScreen({super.key});

  @override
  State<DevCallScreen> createState() => _DevCallScreenState();
}

class _DevCallScreenState extends State<DevCallScreen> {
  final _addrCtrl = TextEditingController();
  final _funcCtrl = TextEditingController();
  final _argsCtrl = TextEditingController();
  final _ouCtrl = TextEditingController(text: '1000');
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;
  String? _txHash;

  @override
  void dispose() {
    _addrCtrl.dispose();
    _funcCtrl.dispose();
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
      List<dynamic> args = [];
      final argsStr = _argsCtrl.text.trim();
      if (argsStr.isNotEmpty) {
        args = jsonDecode(argsStr) as List<dynamic>;
      }
      final ws = context.read<WalletService>();
      final ns = context.read<NetworkService>();
      final hash = await ws.sendContractCall(
        nodeUrl: ns.activeNodeUrl,
        contractAddress: _addrCtrl.text.trim(),
        functionName: _funcCtrl.text.trim(),
        args: args,
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
      appBar: AppBar(title: const Text('Call Contract')),
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
                  Icon(Icons.call_made_rounded, color: cs.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(
                    'Execute a state-changing function on a smart contract.',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  )),
                ]),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addrCtrl,
                decoration: const InputDecoration(
                    labelText: 'Contract Address', hintText: 'oct...'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _funcCtrl,
                decoration: const InputDecoration(
                    labelText: 'Function Name', hintText: 'transfer'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _argsCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Arguments (JSON array)',
                  hintText: '["oct...", 1000]',
                  alignLabelWithHint: true,
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _ouCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Operation Units'),
                validator: (v) => (v == null || int.tryParse(v.trim()) == null)
                    ? 'Enter valid OU'
                    : null,
              ),
              const SizedBox(height: 16),
              if (_error != null) ...[
                _Banner(message: _error!, isError: true),
                const SizedBox(height: 12),
              ],
              if (_txHash != null) ...[
                _Banner(
                    message: 'Call TX submitted!\nHash: $_txHash',
                    isError: false),
                const SizedBox(height: 12),
                TonalButton(label: 'Done', onPressed: () => context.pop()),
              ] else
                TonalButton(
                  label: 'Call Function',
                  icon: Icons.call_made_rounded,
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
