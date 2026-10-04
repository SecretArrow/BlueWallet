import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/wallet_service.dart';
import '../../models/tx_record.dart';
import '../../widgets/octopus_card.dart';
import '../../widgets/tonal_button.dart';

/// Transactions Manager — shows pending transactions with retry/cancel actions.
/// Matches TransactionsManagerActivity.
class TransactionsManagerScreen extends StatefulWidget {
  const TransactionsManagerScreen({super.key});

  @override
  State<TransactionsManagerScreen> createState() =>
      _TransactionsManagerScreenState();
}

class _TransactionsManagerScreenState extends State<TransactionsManagerScreen> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ws = context.watch<WalletService>();

    final pending =
        ws.history.where((t) => t.status == 'pending').toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Transaction Manager')),
      body: pending.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.task_alt_rounded, size: 54, color: cs.outline),
                  const SizedBox(height: 10),
                  Text('No pending transactions',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: pending.length,
              itemBuilder: (ctx, i) => _PendingTxCard(tx: pending[i]),
            ),
    );
  }
}

class _PendingTxCard extends StatelessWidget {
  final TxRecord tx;
  const _PendingTxCard({required this.tx});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: OctopusCard(
        onTap: () => context.push('/tx-detail', extra: tx),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: cs.primary),
                  ),
                  const SizedBox(width: 8),
                  Text('PENDING',
                      style: TextStyle(
                          color: cs.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2)),
                  const Spacer(),
                  Text('${tx.amount} OCT',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                tx.hash,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontFamily: 'monospace',
                    fontSize: 11),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: tx.hash));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Hash copied'),
                              duration: Duration(seconds: 1)),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      label: const Text('Copy Hash',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/tx-detail', extra: tx),
                      icon: const Icon(Icons.open_in_new_rounded, size: 14),
                      label:
                          const Text('Details', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
