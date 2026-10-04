import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/wallet_service.dart';
import '../../services/network_service.dart';
import '../../services/polling_service.dart';
import '../../widgets/tonal_button.dart';

/// Live transaction progress screen.
///
/// Accepts an [extra] map with:
///  `{'txHash': '...', 'amount': '...', 'toAddress': '...', 'opType': '...'}`
///
/// Polls the node via octra_transaction RPC until confirmed or failed.
class TxProgressScreen extends StatefulWidget {
  final Map<String, dynamic>? txData;

  const TxProgressScreen({super.key, this.txData});

  @override
  State<TxProgressScreen> createState() => _TxProgressScreenState();
}

enum _TxStatus { pending, confirmed, failed }

class _TxProgressScreenState extends State<TxProgressScreen>
    with SingleTickerProviderStateMixin {
  _TxStatus _status = _TxStatus.pending;
  String _statusMessage = 'Transaction broadcast. Waiting for confirmation...';
  Timer? _pollTimer;
  int _pollCount = 0;
  bool _showTimeoutPrompt = false;

  int get _maxPolls {
    final ps = context.read<PollingService>();
    final type = widget.txData?['opType']?.toString().toLowerCase() ?? 'send';
    final intervalMs = ps.intervalMs;
    // Calculate max polls based on total timeout threshold / poll interval
    final thresholdMs = (type == 'send' || type == 'token_send')
        ? ps.thresholdSendMs
        : ps.thresholdAdvancedMs;
    return (thresholdMs / intervalMs).ceil();
  }

  Duration get _pollInterval {
    final ps = context.read<PollingService>();
    return Duration(milliseconds: ps.intervalMs);
  }

  late AnimationController _spinCtrl;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    if (widget.txData?['txHash'] != null) {
      _startPolling();
    }
  }

  void _startPolling() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _checkStatus();
    });
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (_pollCount >= _maxPolls) {
        _pollTimer?.cancel();
        if (mounted) {
          setState(() {
            _showTimeoutPrompt = true;
          });
        }
        return;
      }
      _pollCount++;
      _checkStatus();
    });
  }

  Future<void> _checkStatus() async {
    if (_status != _TxStatus.pending) return;
    try {
      final ws = context.read<WalletService>();
      final ns = context.read<NetworkService>();
      final txHash = widget.txData?['txHash']?.toString() ?? '';
      if (txHash.isEmpty) return;

      final result = await ws.lookupTransaction(ns.activeNodeUrl, txHash);

      // Android's queryFinalStatus: handle nested {transaction: {...}} wrapper
      final Map<String, dynamic> txObj =
          (result.containsKey('transaction') && result['transaction'] is Map<String, dynamic>)
              ? result['transaction'] as Map<String, dynamic>
              : result;

      // Aggregate all possible status fields (mirrors Android extractStatusText)
      final status = _extractStatusText(txObj);

      if (_containsAny(status, ['success', 'confirmed', 'final', 'committed', 'accepted', 'applied'])) {
        _pollTimer?.cancel();
        _spinCtrl.stop();
        if (mounted) {
          setState(() {
            _status = _TxStatus.confirmed;
            _statusMessage = 'Transaction confirmed!';
          });
        }
      } else if (_containsAny(status, ['reject', 'fail', 'error', 'invalid'])) {
        _pollTimer?.cancel();
        _spinCtrl.stop();
        String reason = txObj['error']?.toString() ??
            txObj['message']?.toString() ??
            txObj['reason']?.toString() ??
            'Transaction rejected by node';

        // Humanize common errors
        if (reason.contains('nonce too low')) {
          reason = 'Transaction has an invalid sequence (nonce too low).';
        } else if (reason.contains('insufficient balance') ||
            reason.contains('insufficient funds')) {
          reason = 'Insufficient balance to cover transaction and gas fees.';
        } else if (reason.contains('underpriced')) {
          reason = 'Gas fee is too low for current network conditions.';
        }

        if (mounted) {
          setState(() {
            _status = _TxStatus.failed;
            _statusMessage = 'Transaction failed: $reason';
          });
        }
      }
    } catch (e) {
      debugPrint('TxProgress poll error: $e');
    }
  }

  /// Aggregates multiple status fields (mirrors Android's extractStatusText).
  static String _extractStatusText(Map<String, dynamic> tx) {
    final parts = <String>[
      tx['status']?.toString() ?? '',
      tx['tx_status']?.toString() ?? '',
      tx['state']?.toString() ?? '',
      tx['final_status']?.toString() ?? '',
      if (tx['confirmed'] == true) 'confirmed',
      if (tx['rejected'] == true) 'rejected',
    ];
    return parts.where((s) => s.isNotEmpty).join(' | ').toLowerCase();
  }

  static bool _containsAny(String value, List<String> needles) =>
      needles.any((n) => value.contains(n));

  @override
  void dispose() {
    _pollTimer?.cancel();
    _spinCtrl.dispose();
    super.dispose();
  }

  String get _txHash => widget.txData?['txHash']?.toString() ?? '';
  String get _amount => widget.txData?['amount']?.toString() ?? '';
  String get _toAddress => widget.txData?['toAddress']?.toString() ?? '';
  String get _opType => widget.txData?['opType']?.toString() ?? 'standard';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction Status'),
        automaticallyImplyLeading: _status != _TxStatus.pending,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status icon
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: _status == _TxStatus.pending
                    ? RotationTransition(
                        turns: _spinCtrl,
                        child: Icon(Icons.sync_rounded,
                            size: 72, color: cs.primary),
                      )
                    : Icon(
                        _status == _TxStatus.confirmed
                            ? Icons.check_circle_rounded
                            : Icons.error_rounded,
                        size: 72,
                        color: _status == _TxStatus.confirmed
                            ? Colors.green
                            : cs.error,
                      ),
              ),
              const SizedBox(height: 24),

              // Status message
              Text(
                _statusMessage,
                style:
                    tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Details card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _Row('Type', _opType.toUpperCase()),
                    const Divider(height: 16),
                    _Row('Amount', '$_amount OCT'),
                    if (_toAddress.isNotEmpty) ...[
                      const Divider(height: 16),
                      _Row(
                        'To',
                        _toAddress.length > 20
                            ? '${_toAddress.substring(0, 10)}...${_toAddress.substring(_toAddress.length - 10)}'
                            : _toAddress,
                      ),
                    ],
                    if (_txHash.isNotEmpty) ...[
                      const Divider(height: 16),
                      Row(
                        children: [
                          Text('TX Hash',
                              style:
                                  TextStyle(color: cs.onSurfaceVariant)),
                          const Spacer(),
                          Flexible(
                            child: GestureDetector(
                              onTap: () {
                                Clipboard.setData(
                                    ClipboardData(text: _txHash));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Hash copied'),
                                      duration: Duration(seconds: 2)),
                                );
                              },
                              child: Text(
                                _txHash.length > 16
                                    ? '${_txHash.substring(0, 8)}...${_txHash.substring(_txHash.length - 8)}'
                                    : _txHash,
                                style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 32),

              if (_showTimeoutPrompt && _status == _TxStatus.pending) ...[
                Text(
                  'This transaction is taking longer than usual. Would you like to keep waiting or return to home?',
                  textAlign: TextAlign.center,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => context.pop(),
                        child: const Text('Return Home'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          setState(() {
                            _showTimeoutPrompt = false;
                            _pollCount = 0;
                          });
                          _startPolling();
                        },
                        child: const Text('Keep Waiting'),
                      ),
                    ),
                  ],
                ),
              ] else if (_status != _TxStatus.pending)
                TonalButton(
                  label: 'Go to Home',
                  icon: Icons.home_rounded,
                  onPressed: () => context.pop(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
