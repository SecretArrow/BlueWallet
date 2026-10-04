import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/wallet_service.dart';
import '../../services/network_service.dart';
import '../../widgets/octra_card.dart';

/// Auto Scan screen — configures periodic background refresh that persists
/// even after leaving this screen. The timer lives in WalletService so
/// dashboard and history refresh silently in the background.
class AutoScanScreen extends StatefulWidget {
  const AutoScanScreen({super.key});

  @override
  State<AutoScanScreen> createState() => _AutoScanScreenState();
}

// Interval options: label → minutes (0 = Never / stop)
const _kIntervals = <String, int>{
  '1 minute': 1,
  '5 minutes': 5,
  '10 minutes': 10,
  '20 minutes': 20,
  '30 minutes': 30,
  '60 minutes': 60,
  'Never': 0,
};

class _AutoScanScreenState extends State<AutoScanScreen> {
  String _labelForMinutes(int m) {
    if (m == 0) return 'Never';
    for (final e in _kIntervals.entries) {
      if (e.value == m) return e.key;
    }
    return '$m minutes';
  }

  void _applyInterval(String label) {
    final minutes = _kIntervals[label] ?? 0;
    final ws = context.read<WalletService>();
    final ns = context.read<NetworkService>();
    if (minutes == 0) {
      ws.stopAutoScan();
    } else {
      ws.startAutoScan(minutes, ns.activeNodeUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ws = context.watch<WalletService>();
    final running = ws.autoScanRunning;
    final selectedLabel = _labelForMinutes(ws.autoScanMinutes);

    return Scaffold(
      appBar: AppBar(title: const Text('Auto Scan')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Info banner
              OctopusCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.autorenew_rounded, color: cs.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Automatically refresh wallet balance, history, and '
                        'tokens in the background at the selected interval. '
                        'Runs silently even after leaving this screen.',
                        style:
                            TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Interval selector
              Text('Scan Interval',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              OctopusCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedLabel,
                    isExpanded: true,
                    icon: Icon(Icons.keyboard_arrow_down_rounded,
                        color: cs.primary),
                    items: _kIntervals.keys
                        .map((label) => DropdownMenuItem(
                              value: label,
                              child: Text(label),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) _applyInterval(v);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Status card
              OctopusCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: running ? Colors.green : cs.outline,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          running
                              ? 'Scanning every $selectedLabel'
                              : 'Idle — select an interval to start',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: running ? Colors.green : cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if (ws.autoScanLastError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        ws.autoScanLastError!,
                        style: TextStyle(color: cs.error, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _Stat(
                            label: 'Checks', value: '${ws.autoScanCheckCount}'),
                        _Stat(
                            label: 'New TXs',
                            value: '${ws.autoScanNewTxCount}'),
                        _Stat(
                            label: 'Last Check',
                            value: ws.autoScanLastCheck ?? '--:--:--'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: cs.onSurface)),
        Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
      ],
    );
  }
}
