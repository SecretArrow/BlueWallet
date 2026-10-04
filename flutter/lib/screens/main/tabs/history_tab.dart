import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../models/tx_record.dart';
import '../../../services/wallet_service.dart';
import '../../../services/network_service.dart';
import '../../../widgets/adaptive_body.dart';

/// History tab — transaction history list with pull-to-refresh and date grouping.
///
/// On first mount it always schedules a background network refresh so cached
/// rows are shown instantly and then seamlessly replaced with fresh data.
class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  bool _firstLoadTriggered = false;

  @override
  void initState() {
    super.initState();
    // Always schedule a network refresh on first appearance.
    // We use addPostFrameCallback so providers are mounted before we read them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_firstLoadTriggered) {
        _firstLoadTriggered = true;
        _refresh();
      }
    });
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final ws = context.read<WalletService>();
    final ns = context.read<NetworkService>();
    await ws.loadHistory(ns.activeNodeUrl);
  }

  // ── Build a flat list that interleaves date-header items ─────────────────

  /// Represents a date section header in the list.
  static const _dateHeaderType = 'date_header';

  /// Returns a mixed list of either [String] (date labels) or [TxRecord].
  List<dynamic> _buildListItems(List<TxRecord> txs) {
    if (txs.isEmpty) return [];
    final items = <dynamic>[];
    String? lastLabel;
    for (final tx in txs) {
      final label = _dayLabel(tx.timestamp);
      if (label != lastLabel) {
        items.add({'type': _dateHeaderType, 'label': label});
        lastLabel = label;
      }
      items.add(tx);
    }
    return items;
  }

  static String _dayLabel(int tsMs) {
    if (tsMs == 0) return 'Unknown date';
    final dt = DateTime.fromMillisecondsSinceEpoch(tsMs);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) {
      const names = [
        'Sunday',
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday'
      ];
      return names[dt.weekday % 7];
    }
    // e.g. "March 9, 2026"
    final months = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return '${months[dt.month]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WalletService>();
    final cs = Theme.of(context).colorScheme;
    final txs = ws.history;
    final myAddr = ws.activeWallet?.address ?? '';

    // Show full-screen spinner only on the very first load with zero cache.
    if (txs.isEmpty && ws.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (txs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded,
                size: 56, color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text('No transactions yet',
                style: TextStyle(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                    fontSize: 14)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    final items = _buildListItems(txs);

    return AdaptiveBody(
      child: RefreshIndicator(
        color: cs.primary,
        onRefresh: _refresh,
        child: Stack(
          children: [
            ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                if (item is Map && item['type'] == _dateHeaderType) {
                  return _DateHeader(label: item['label'] as String);
                }
                return _HistoryRow(tx: item as TxRecord, myAddress: myAddr);
              },
            ),
            // Subtle top-of-list spinner when refreshing but list has data.
            if (ws.loading)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: cs.primary,
                  backgroundColor: cs.primary.withValues(alpha: 0.12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  Date section header
// ────────────────────────────────────────────────────────────────────────────

class _DateHeader extends StatelessWidget {
  final String label;
  const _DateHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  Transaction row
// ────────────────────────────────────────────────────────────────────────────

class _HistoryRow extends StatelessWidget {
  final TxRecord tx;
  final String myAddress;
  const _HistoryRow({required this.tx, required this.myAddress});

  bool get _isSent => tx.type == 'sent' || tx.fromAddress == myAddress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => context.push('/tx-detail', extra: tx),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Direction icon 28dp (no container background)
            Icon(
              _isSent
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              size: 28,
              color: _isSent ? Colors.red[300] : Colors.green[300],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Amount + time (right)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_isSent ? '-' : '+'}${_formatAmount(tx.amount)} OCT',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _isSent ? Colors.red[300] : Colors.green[300],
                        ),
                      ),
                      Text(
                        _formatTime(tx.timestamp),
                        style:
                            TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Row 2: Op type + status badge
                  Row(
                    children: [
                      Text(
                        _typeLabel(tx.opType),
                        style:
                            TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(width: 8),
                      _StatusChip(status: tx.status),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Row 3: Counterparty address (monospace, ellipsis)
                  Text(
                    _counterparty,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _counterparty => _isSent ? tx.toAddress : tx.fromAddress;

  String _formatAmount(String amount) {
    if (amount.contains('.')) return amount;
    final i = int.tryParse(amount);
    if (i != null) return WalletService.formatOct(i);
    return amount;
  }

  String _formatTime(int ts) {
    if (ts == 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  String _typeLabel(String? opType) {
    switch (opType) {
      case 'stake':
        return 'Stake';
      case 'unstake':
        return 'Unstake';
      case 'encrypt':
        return 'Encrypt';
      case 'decrypt':
        return 'Decrypt';
      case 'stealth':
        return 'Stealth';
      case 'deploy':
        return 'Deploy';
      case 'call':
        return 'Contract call';
      default:
        return 'Transfer';
    }
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  Status chip
// ────────────────────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = _resolve(status, Theme.of(context).colorScheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  static (String, Color) _resolve(String raw, ColorScheme cs) {
    switch (raw.toLowerCase()) {
      case 'confirmed':
      case 'sent':
        return ('Confirmed', Colors.green);
      case 'pending':
      case 'processing':
        return ('Pending', Colors.orange);
      case 'failed':
      case 'error':
        return ('Failed', cs.error);
      default:
        return (raw, cs.onSurfaceVariant);
    }
  }
}
