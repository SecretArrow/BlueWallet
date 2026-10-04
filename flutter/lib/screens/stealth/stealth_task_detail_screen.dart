import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/wallet_service.dart';
import '../../services/data_usage_service.dart';
import '../../widgets/tonal_button.dart';
import '../../widgets/octopus_card.dart';
import '../../widgets/adaptive_body.dart';

/// Stealth Task Detail screen — displays detailed information about a stealth transaction.
class StealthTaskDetailScreen extends StatefulWidget {
  final String taskId;

  const StealthTaskDetailScreen({super.key, required this.taskId});

  @override
  State<StealthTaskDetailScreen> createState() =>
      _StealthTaskDetailScreenState();
}

class _StealthTaskDetailScreenState extends State<StealthTaskDetailScreen> {
  final DataUsageService _dataUsageService = DataUsageService.instance;

  DataUsage? _sessionUsage;
  bool _isLoadingDataUsage = true;

  @override
  void initState() {
    super.initState();
    _loadDataUsage();
  }

  Future<void> _loadDataUsage() async {
    setState(() => _isLoadingDataUsage = true);
    try {
      final sessionUsage = await _dataUsageService.getSessionUsage();
      setState(() {
        _sessionUsage = sessionUsage;
        _isLoadingDataUsage = false;
      });
    } catch (e) {
      setState(() => _isLoadingDataUsage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ws = context.watch<WalletService>();

    // Find the transaction in history
    final tx = ws.history.firstWhere(
      (t) => t.hash == widget.taskId,
      orElse: () => throw Exception('Transaction not found'),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stealth Task'),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: AdaptiveBody(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OctopusCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDetailRow(
                      context,
                      'Task ID',
                      tx.hash,
                      monospace: true,
                    ),
                    _buildDivider(context),
                    _buildDetailRow(
                      context,
                      'Recipient',
                      tx.toAddress.isEmpty ? '-' : tx.toAddress,
                      monospace: true,
                    ),
                    _buildDivider(context),
                    _buildDetailRow(
                      context,
                      'Amount',
                      '${tx.amount} OCT',
                    ),
                    _buildDivider(context),
                    _buildDetailRow(
                      context,
                      'Status',
                      tx.status,
                      bold: true,
                    ),
                    _buildDivider(context),
                    // Data Usage Section
                    _buildDataUsageSection(context),
                    _buildDivider(context),
                    _buildDetailRow(
                      context,
                      'Message',
                      tx.memo == null || tx.memo!.isEmpty ? '-' : tx.memo!,
                    ),
                    if (tx.blockHash != null && tx.blockHash!.isNotEmpty) ...[
                      _buildDivider(context),
                      _buildDetailRow(
                        context,
                        'Block Hash',
                        tx.blockHash!,
                        monospace: true,
                      ),
                    ],
                    _buildDivider(context),
                    _buildDetailRow(
                      context,
                      'Created',
                      _formatTimestamp(tx.timestamp),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TonalButton(
                label: 'Refresh Data Usage',
                icon: Icons.refresh_rounded,
                onPressed: _loadDataUsage,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataUsageSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Data Usage',
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (_isLoadingDataUsage)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sent (TX)',
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _sessionUsage?.formattedTx ?? '0 B',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Received (RX)',
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _sessionUsage?.formattedRx ?? '0 B',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total',
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _sessionUsage?.formattedTotal ?? '0 B',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    String label,
    String value, {
    bool monospace = false,
    bool bold = false,
  }) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            color: cs.onSurface,
            fontFamily: monospace ? 'monospace' : null,
            fontWeight: bold ? FontWeight.bold : null,
          ),
          maxLines: monospace ? 3 : null,
          overflow: monospace ? TextOverflow.ellipsis : null,
        ),
      ],
    );
  }

  Widget _buildDivider(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Divider(
        height: 1,
        color: cs.onSurface.withOpacity(0.15),
      ),
    );
  }

  String _formatTimestamp(int timestamp) {
    if (timestamp <= 0) return '-';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
  }
}
