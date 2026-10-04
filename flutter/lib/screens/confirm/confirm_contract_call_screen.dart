import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/local_web_server_service.dart';
import '../../services/wallet_service.dart';
import '../../services/network_service.dart';
import '../../services/pin_service.dart';
import '../../services/biometric_service.dart';
import '../../widgets/tonal_button.dart';
import '../../widgets/octopus_card.dart';
import '../../widgets/adaptive_body.dart';

class ConfirmContractCallScreen extends StatefulWidget {
  final String requestId;
  const ConfirmContractCallScreen({super.key, required this.requestId});

  @override
  State<ConfirmContractCallScreen> createState() => _ConfirmContractCallScreenState();
}

class _ConfirmContractCallScreenState extends State<ConfirmContractCallScreen> {
  bool _loading = false;
  String? _error;
  String? _successHash;

  @override
  void dispose() {
    // If the screen is dismissed without action, reject the transaction safely
    final req = LocalWebServerService.pendingRequests[widget.requestId];
    if (req != null && !req.completer.isCompleted) {
      req.completer.complete({'success': false, 'error': 'User cancelled request'});
    }
    super.dispose();
  }

  Future<void> _handleConfirm() async {
    setState(() {
      _error = null;
    });

    final req = LocalWebServerService.pendingRequests[widget.requestId];
    if (req == null) {
      setState(() => _error = 'Transaction request not found or expired.');
      return;
    }

    // Try Biometrics first if enabled
    bool authenticated = false;
    String? pin;

    if (await BiometricService.isEnabled()) {
      pin = await BiometricService.authenticateAndGetPin(
        reason: 'Authenticate to approve contract call',
      );
      if (pin != null) {
        authenticated = true;
      }
    }

    // Fallback to PIN Entry
    if (!authenticated) {
      pin = await _promptPinEntry();
      if (pin == null) {
        // User cancelled PIN entry
        return;
      }
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

    if (!authenticated) return;

    setState(() {
      _loading = true;
    });

    try {
      final ws = context.read<WalletService>();
      final ns = context.read<NetworkService>();

      List<dynamic> parsedArgs = [];
      try {
        parsedArgs = jsonDecode(req.params) as List<dynamic>;
      } catch (e) {
        throw Exception('Invalid transaction parameters format');
      }

      final hash = await ws.sendContractCall(
        nodeUrl: ns.activeNodeUrl,
        contractAddress: req.address,
        functionName: req.method,
        args: parsedArgs,
        ou: req.ou,
      );

      // Auto-refresh wallet balance in background
      ws.refresh(ns.activeNodeUrl).catchError((_) => null);

      if (!req.completer.isCompleted) {
        req.completer.complete({
          'success': true,
          'tx_hash': hash,
        });
      }

      setState(() {
        _successHash = hash;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transaction successfully signed and submitted!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      final errorMsg = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _error = errorMsg;
      });
      // Do not complete the request immediately as user can retry or cancel
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _handleCancel() async {
    final req = LocalWebServerService.pendingRequests[widget.requestId];
    if (req != null && !req.completer.isCompleted) {
      req.completer.complete({'success': false, 'error': 'Transaction rejected by user'});
    }
    if (mounted) {
      context.pop();
    }
  }

  Future<String?> _promptPinEntry() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Enter Wallet PIN'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'PIN Code',
                counterText: '',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'PIN is required';
                if (v.trim().length < 4) return 'PIN must be at least 4 digits';
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
        );
      },
    );
  }

  String _formatParams(String paramsStr) {
    try {
      final parsed = jsonDecode(paramsStr);
      final encoder = const JsonEncoder.withIndent('  ');
      return encoder.convert(parsed);
    } catch (_) {
      return paramsStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final req = LocalWebServerService.pendingRequests[widget.requestId];

    if (req == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transaction Confirmation')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: OctopusCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline_rounded, size: 48, color: cs.error),
                  const SizedBox(height: 16),
                  const Text(
                    'Request Expired',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This transaction request has expired, was already resolved, or does not exist.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => context.pop(),
                      child: const Text('Go Back'),
                    ),
                  ),
                ],
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
              onPressed: _handleCancel,
            ),
        ],
      ),
      body: AdaptiveBody(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Premium warning/info header card
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
                      child: Icon(Icons.security_rounded, color: cs.onPrimaryContainer, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'External Request',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          Text(
                            'A local application or browser extension is requesting a smart contract call.',
                            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Tx Details Card
              OctopusCard(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CONTRACT ADDRESS',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      req.address,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'METHOD NAME',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        req.method,
                        style: TextStyle(
                          fontSize: 14,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'PARAMETERS',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.onSurface.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _formatParams(req.params),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
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
                              const Text(
                                'AMOUNT',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${req.amount} OCT',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'GAS LIMIT (OU)',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                req.ou,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Error feedback
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
                        child: Text(
                          _error!,
                          style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Success State
              if (_successHash != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.check_circle_rounded, color: Colors.green),
                          SizedBox(width: 8),
                          Text(
                            'Transaction Submitted!',
                            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'TRANSACTION HASH',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        _successHash!,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                TonalButton(
                  label: 'Done',
                  onPressed: () => context.pop(),
                ),
              ] else ...[
                // Action Buttons
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
    );
  }
}
