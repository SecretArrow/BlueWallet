import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/tx_record.dart';
import '../../widgets/octopus_card.dart';

/// History Detail screen — shows all fields of a TxRecord.
/// Passed via router `extra` as a TxRecord instance.
class HistoryDetailScreen extends StatelessWidget {
  final TxRecord? tx;
  const HistoryDetailScreen({super.key, this.tx});

  String _formatTimestamp(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${dt.year}-${_p(dt.month)}-${_p(dt.day)} '
        '${_p(dt.hour)}:${_p(dt.minute)}:${_p(dt.second)}';
  }

  String _p(int v) => v.toString().padLeft(2, '0');

  Color _statusColor(String s, ColorScheme cs) {
    switch (s.toLowerCase()) {
      case 'confirmed':
      case 'sent':
        return Colors.green;
      case 'failed':
      case 'error':
        return cs.error;
      case 'pending':
        return Colors.orange;
      default:
        return cs.primary;
    }
  }

  String _statusLabel(String s) {
    switch (s.toLowerCase()) {
      case 'confirmed':
        return 'CONFIRMED';
      case 'sent':
        return 'SENT';
      case 'pending':
        return 'PENDING';
      case 'failed':
        return 'FAILED';
      case 'error':
        return 'ERROR';
      default:
        return s.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (tx == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transaction')),
        body: const Center(child: Text('Transaction not found')),
      );
    }

    final isSent = tx!.type == 'sent' || tx!.type == 'send';

    return Scaffold(
      appBar: AppBar(title: const Text('Transaction Detail')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Header
              OctopusCard(
                padding:
                    const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor:
                          (isSent ? cs.error : Colors.green).withOpacity(0.12),
                      child: Icon(
                        isSent
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        color: isSent ? cs.error : Colors.green,
                        size: 26,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${isSent ? '-' : '+'} ${tx!.amount} OCT',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: isSent ? cs.error : Colors.green,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _statusColor(tx!.status, cs).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _statusLabel(tx!.status),
                        style: TextStyle(
                          color: _statusColor(tx!.status, cs),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Detail rows
              OctopusCard(
                child: Column(
                  children: [
                    _Row(
                        label: 'Hash',
                        value: tx!.hash,
                        monospace: true,
                        copyable: true),
                    const Divider(height: 1),
                    _Row(label: 'Type', value: tx!.type.toUpperCase()),
                    const Divider(height: 1),
                    _Row(
                        label: 'From',
                        value: tx!.fromAddress,
                        monospace: true,
                        copyable: true),
                    const Divider(height: 1),
                    _Row(
                        label: 'To',
                        value: tx!.toAddress,
                        monospace: true,
                        copyable: true),
                    if ((tx!.memo ?? '').isNotEmpty) ...[
                      const Divider(height: 1),
                      _Row(label: 'Memo', value: tx!.memo ?? ''),
                    ],
                    const Divider(height: 1),
                    _Row(label: 'Date', value: _formatTimestamp(tx!.timestamp)),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Explorer link
              OutlinedButton.icon(
                onPressed: () {
                  final url = Uri.parse('https://octra.network/tx/${tx!.hash}');
                  launchUrl(url, mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('View in Explorer'),
              ),
              // Bottom padding for Android system navigation bar
              SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
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
  final bool monospace;
  final bool copyable;
  const _Row(
      {required this.label,
      required this.value,
      this.monospace = false,
      this.copyable = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(label,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: monospace ? 'monospace' : null,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (copyable)
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Copied'), duration: Duration(seconds: 1)),
                );
              },
              child: Icon(Icons.copy_rounded, size: 16, color: cs.primary),
            ),
        ],
      ),
    );
  }
}
