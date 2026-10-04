import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/wallet_service.dart';
import '../../services/network_service.dart';
import '../../widgets/octopus_card.dart';
import '../../widgets/tonal_button.dart';
import '../../widgets/adaptive_body.dart';

/// Stealth Scan screen — scans the blockchain for incoming stealth funds
/// via the octra_stealthOutputs RPC endpoint.
class StealthScanScreen extends StatefulWidget {
  const StealthScanScreen({super.key});

  @override
  State<StealthScanScreen> createState() => _StealthScanScreenState();
}

class _StealthScanScreenState extends State<StealthScanScreen> {
  bool _scanning = false;
  bool _done = false;
  String? _error;
  List<Map<String, dynamic>> _found = [];

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _done = false;
      _error = null;
      _found = [];
    });

    try {
      final ws = context.read<WalletService>();
      final ns = context.read<NetworkService>();
      final results = await ws.scanStealthOutputs(ns.activeNodeUrl);
      if (mounted) {
        setState(() {
          _found = results;
          _scanning = false;
          _done = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _done = true;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Stealth Scan')),
      body: AdaptiveBody(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OctopusCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, color: cs.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Scan the blockchain to detect incoming stealth payments sent to your stealth address.',
                        style:
                            TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (_error != null) ...[
                OctopusCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.error_rounded, color: cs.error, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_error!,
                            style: TextStyle(color: cs.error, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              OctopusCard(
                padding:
                    const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                child: Column(
                  children: [
                    if (_scanning) ...[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 14),
                      Text('Scanning stealth outputs...',
                          style: TextStyle(
                              color: cs.primary, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text(
                        'Checking ECDH match for each output',
                        style:
                            TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                      ),
                    ] else if (_done) ...[
                      Icon(Icons.check_circle_rounded,
                          color: Colors.green, size: 48),
                      const SizedBox(height: 8),
                      Text(
                        'Scan complete',
                        style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_found.length} stealth payment(s) found',
                        style:
                            TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                      ),
                    ] else ...[
                      Icon(Icons.radar_rounded, size: 48, color: cs.outline),
                      const SizedBox(height: 8),
                      Text(
                        'Ready to scan',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              if (_done && _found.isNotEmpty) ...[
                const SizedBox(height: 16),
                Expanded(
                  child: OctopusCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text('Found Payments',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                  fontSize: 14)),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _found.length,
                            itemBuilder: (ctx, i) {
                              final p = _found[i];
                              return ListTile(
                                leading: Icon(Icons.arrow_downward_rounded,
                                    color: Colors.green, size: 20),
                                title: Text('${p['amount']} OCT'),
                                subtitle: Text(
                                    'TX: ${_truncHash(p['tx_hash'] ?? '')}',
                                    style: const TextStyle(
                                        fontFamily: 'monospace', fontSize: 12)),
                                trailing: IconButton(
                                  icon: Icon(Icons.copy_rounded,
                                      size: 16, color: cs.primary),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(
                                        text: p['tx_hash'] ?? ''));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('Hash copied'),
                                          duration: Duration(seconds: 1)),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                const Spacer(),
              ],
              const SizedBox(height: 16),
              if (!_scanning)
                TonalButton(
                  label: _done ? 'Scan Again' : 'Start Scan',
                  icon: Icons.search_rounded,
                  onPressed: _startScan,
                ),
              if (_scanning)
                TonalButton(
                  label: 'Scanning...',
                  loading: true,
                  onPressed: null,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _truncHash(String h) =>
      h.length > 16 ? '${h.substring(0, 8)}...${h.substring(h.length - 8)}' : h;
}
