import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/biometric_service.dart';
import '../../services/network_service.dart';
import '../../services/pin_service.dart';
import '../../services/wallet_service.dart';
import '../../widgets/adaptive_body.dart';
import '../../widgets/octopus_card.dart';
import '../../widgets/tonal_button.dart';

/// Approval screen for a contract call from a dApp.
///
/// Preferred invocation passes the call details via router `extra`:
/// `{address, method, params (List), amount, ou, origin}`.
/// The legacy `requestId` query param (local-web-server flow) no longer
/// resolves — the server was removed — so it shows an expired state
/// instead of hanging. Dismiss / back == reject (cancel != approve).
class ConfirmContractCallScreen extends StatefulWidget {
  final String requestId;
  final Map<String, dynamic>? details;
  const ConfirmContractCallScreen(
      {super.key, required this.requestId, this.details});

  @override
  State<ConfirmContractCallScreen> createState() =>
      _ConfirmContractCallScreenState();
}

class _ConfirmContractCallScreenState extends State<ConfirmContractCallScreen> {
  bool _loading = false;
  bool _confirming = false;
  String? _error;
  String? _successHash;

  Map<String, dynamic>? get _req {
    final d = widget.details;
    if (d == null) return null;
    return {
      'address': d['address']?.toString() ?? '',
      'method': d['method']?.toString() ?? '',
      'params': d['params'] is String
          ? d['params'] as String
          : jsonEncode(d['params'] ?? []),
      'amount': d['amount']?.toString() ?? '0',
      'ou': d['ou']?.toString() ?? '1000',
      'origin': d['origin']?.toString() ?? '',
    };
  }

  Future<void> _handleConfirm() async {
    if (_confirming || _loading) return; // double-tap guard
    final req = _req;
    if (req == null) {
      setState(() => _error = 'Transaction request not found or expired.');
      return;
    }
    setState(() => _error = null);

    bool authenticated = false;
    String? pin;
    try {
      if (await BiometricService.isEnabled()) {
        pin = await BiometricService.authenticateAndGetPin(
          reason: 'Authenticate to approve contract call',
        );
        if (pin != null) authenticated = true;
      }
    } catch (_) {
      authenticated = false;
    }
    if (!authenticated) {
      if (!mounted) return;
      pin = await _promptPinEntry();
      if (pin == null) return; // user cancelled PIN entry == reject path
      final isPinValid = await PinService.verifyPin(pin);
      if (!isPinValid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid PIN code'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      authenticated = true;
    }
    if (!authenticated || !mounted) return;
    setState(() {
      _loading = true;
      _confirming = true;
    });
    try {
      final ws = context.read<WalletService>();
      final ns = context.read<NetworkService>();
      List<dynamic> parsedArgs = [];
      try {
        parsedArgs = jsonDecode(req['params'] as String) as List<dynamic>;
      } catch (_) {
        throw Exception('Invalid transaction parameters format');
      }
      final hash = await ws.sendContractCall(
        nodeUrl: ns.activeNodeUrl,
        contractAddress: req['address'] as String,
        functionName: req['method'] as String,
        args: parsedArgs,
        ou: req['ou'] as String,
      );
      unawaited(ws.refresh(ns.activeNodeUrl).then((_) {}).catchError((_) {}));
      if (!mounted) return;
      setState(() => _successHash = hash);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transaction successfully signed and submitted!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _confirming = false;
        });
      }
    }
  }

  void _handleCancel() {
    if (mounted) context.pop(false);
  }

  Future<String?> _promptPinEntry() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Enter Wallet PIN'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 16,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'PIN Code',
                counterText: '',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'PIN is required';
                if (v.trim().length < 6) return 'PIN minimal 6 digit';
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.pop(ctx, controller.text.trim());
                }
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  String _formatParams(String paramsStr) {
    try {
      final parsed = jsonDecode(paramsStr);
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(parsed);
    } catch (_) {
      return paramsStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final req = _req;

    if (req == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transaction Confirmation')),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: OctopusCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 48, color: cs.error),
                    const SizedBox(height: 16),
                    const Text('Request Expired',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                      'This transaction request has expired, was already resolved, or does not exist.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => context.pop(false),
                        child: const Text('Go Back'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm Transaction'),
        automaticallyImplyLeading: false,
        actions: [
          if (_successHash == null)
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: _loading ? null : _handleCancel,
            ),
        ],
      ),
      body: SafeArea(
        child: AdaptiveBody(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OctopusCard(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.security_rounded,
                            color: cs.onPrimaryContainer, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('External Request',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14)),
                            Text(
                              (req['origin'] as String).isEmpty
                                  ? 'A dApp is requesting a smart contract call.'
                                  : 'Origin: ${req['origin']}',
                              style: TextStyle(
                                  fontSize: 11, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                OctopusCard(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('CONTRACT ADDRESS',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0)),
                      const SizedBox(height: 4),
                      SelectableText(req['address'] as String,
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 16),
                      const Text('METHOD NAME',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(req['method'] as String,
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                color: cs.primary)),
                      ),
                      const SizedBox(height: 16),
                      const Text('PARAMETERS',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0)),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.onSurface.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        constraints: const BoxConstraints(maxHeight: 180),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _formatParams(req['params'] as String),
                            style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                color: cs.onSurfaceVariant),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('AMOUNT',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.0)),
                                const SizedBox(height: 2),
                                Text('${req['amount']} OCT',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('GAS LIMIT (OU)',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.0)),
                                const SizedBox(height: 2),
                                Text(req['ou'] as String,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_rounded, color: cs.onErrorContainer),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_error!,
                              style: TextStyle(
                                  color: cs.onErrorContainer, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_successHash != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.green.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.check_circle_rounded,
                                color: Colors.green),
                            SizedBox(width: 8),
                            Text('Transaction Submitted!',
                                style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text('TRANSACTION HASH',
                            style: TextStyle(
                                fontSize: 9, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        SelectableText(_successHash!,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 11)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  TonalButton(
                    label: 'Done',
                    onPressed: () => context.pop(true),
                  ),
                ] else ...[
                  TonalButton(
                    label: 'Sign and Approve',
                    icon: Icons.vpn_key_rounded,
                    loading: _loading,
                    onPressed: _loading ? null : _handleConfirm,
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _loading ? null : _handleCancel,
                    child: const Text('Reject Transaction'),
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
