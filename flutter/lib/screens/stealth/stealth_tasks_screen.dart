import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/wallet_service.dart';
import '../../widgets/octopus_card.dart';
import '../../widgets/adaptive_body.dart';

/// Stealth Tasks screen — lists all stealth transactions from history.
/// Read from the local database (real tx records, no mock data).
class StealthTasksScreen extends StatelessWidget {
  const StealthTasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ws = context.watch<WalletService>();
    final stealthTxs =
        ws.history.where((tx) => tx.opType == 'stealth').toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Stealth Tasks')),
      body: AdaptiveBody(
        child: stealthTxs.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.visibility_off_rounded,
                        size: 54, color: cs.outline),
                    const SizedBox(height: 12),
                    Text('No stealth transactions',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: stealthTxs.length,
                itemBuilder: (ctx, i) {
                  final t = stealthTxs[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: OctopusCard(
                      onTap: () =>
                          context.push('/stealth-task-detail?id=${t.hash}'),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              _statusColor(t.status, cs).withOpacity(0.2),
                          child: Icon(_statusIcon(t.status),
                              color: _statusColor(t.status, cs), size: 20),
                        ),
                        title: Text(
                            '${WalletService.formatOct(int.tryParse(t.amount) ?? 0)} OCT',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          t.hash.length > 20
                              ? '${t.hash.substring(0, 10)}...${t.hash.substring(t.hash.length - 8)}'
                              : t.hash,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              t.status.toUpperCase(),
                              style: TextStyle(
                                color: _statusColor(t.status, cs),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _formatTs(t.timestamp),
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  static Color _statusColor(String s, ColorScheme cs) {
    switch (s) {
      case 'confirmed':
        return Colors.green;
      case 'failed':
        return cs.error;
      default:
        return cs.primary;
    }
  }

  static IconData _statusIcon(String s) {
    switch (s) {
      case 'confirmed':
        return Icons.check_circle_outline_rounded;
      case 'failed':
        return Icons.error_outline_rounded;
      default:
        return Icons.hourglass_empty_rounded;
    }
  }

  static String _formatTs(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}
