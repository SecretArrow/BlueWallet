import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/wallet_service.dart';
import '../../services/network_service.dart';
import '../../widgets/tonal_button.dart';
import '../../widgets/octopus_card.dart';
import '../../widgets/adaptive_body.dart';

/// View Contract screen — read-only contract call.
class DevViewScreen extends StatefulWidget {
  const DevViewScreen({super.key});

  @override
  State<DevViewScreen> createState() => _DevViewScreenState();
}

class _DevViewScreenState extends State<DevViewScreen> {
  final _addrCtrl = TextEditingController();
  final _funcCtrl = TextEditingController();
  final _argsCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;
  String? _result;

  @override
  void dispose() {
    _addrCtrl.dispose();
    _funcCtrl.dispose();
    _argsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      List<dynamic> args = [];
      final argsStr = _argsCtrl.text.trim();
      if (argsStr.isNotEmpty) {
        args = jsonDecode(argsStr) as List<dynamic>;
      }
      final ws = context.read<WalletService>();
      final ns = context.read<NetworkService>();
      final res = await ws.contractView(
        nodeUrl: ns.activeNodeUrl,
        contractAddress: _addrCtrl.text.trim(),
        functionName: _funcCtrl.text.trim(),
        args: args,
      );
      if (mounted) {
        setState(() {
          _result = const JsonEncoder.withIndent('  ').convert(res);
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
    return Scaffold(
      appBar: AppBar(title: const Text('View Contract')),
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
                  Icon(Icons.visibility_rounded, color: cs.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(
                    'Read-only call to view contract state without a transaction.',
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
                    labelText: 'Function Name', hintText: 'balance_of'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _argsCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Arguments (JSON array)',
                  hintText: '["oct..."]',
                  alignLabelWithHint: true,
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              const SizedBox(height: 16),
              if (_error != null) ...[
                _Banner(message: _error!, isError: true),
                const SizedBox(height: 12),
              ],
              if (_result != null) ...[
                const Text('Result:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(
                    _result!,
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  TextButton.icon(
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _result!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Copied'),
                            duration: Duration(seconds: 1)),
                      );
                    },
                  ),
                ]),
                const SizedBox(height: 12),
              ],
              TonalButton(
                label: 'View',
                icon: Icons.visibility_rounded,
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
