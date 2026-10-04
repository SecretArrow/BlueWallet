import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/wallet_service.dart';
import '../../widgets/tonal_button.dart';
import '../../widgets/adaptive_body.dart';

/// Export screen — lets the user view and back up their private key.
/// Matches Android ExportWalletsActivity.
class ExportWalletScreen extends StatefulWidget {
  final String? walletId;
  const ExportWalletScreen({super.key, this.walletId});

  @override
  State<ExportWalletScreen> createState() => _ExportWalletScreenState();
}

class _ExportWalletScreenState extends State<ExportWalletScreen> {
  bool _revealed = false;
  String? _sk;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadKey();
  }

  Future<void> _loadKey() async {
    final ws = context.read<WalletService>();
    final walletId = widget.walletId ?? ws.activeWallet?.id;
    if (walletId == null) return;
    final sk = await ws.getPrivateKey(walletId);
    if (mounted)
      setState(() {
        _sk = sk;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ws = context.watch<WalletService>();
    final wallet = ws.activeWallet;

    return Scaffold(
      appBar: AppBar(title: const Text('Export Wallet')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : AdaptiveBody(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Warning banner
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: cs.error, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Never share your private key with anyone. '
                              'Anyone with this key has full control of your wallet.',
                              style: TextStyle(
                                  color: cs.onErrorContainer, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (wallet != null) ...[
                      Text('Wallet',
                          style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 8),
                      _InfoBox(label: 'Name', value: wallet.name),
                      const SizedBox(height: 8),
                      _InfoBox(
                        label: 'Address',
                        value: wallet.address,
                        monospace: true,
                        canCopy: true,
                      ),
                      const SizedBox(height: 20),
                      Text('Private Key (Base64)',
                          style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 8),
                      _InfoBox(
                        label: '',
                        value: _revealed
                            ? (_sk ?? 'Not found')
                            : '• • • • • • • • • • • •  HIDDEN  • • • • • • • • • • • •',
                        monospace: true,
                        canCopy: _revealed,
                        copyValue: _sk,
                      ),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                          child: TonalButton(
                            label: _revealed ? 'Hide' : 'Reveal Private Key',
                            icon: _revealed
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            onPressed: () =>
                                setState(() => _revealed = !_revealed),
                          ),
                        ),
                        if (_revealed && _sk != null) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: TonalButton(
                              label: 'Share Backup',
                              icon: Icons.share_rounded,
                              onPressed: _shareBackup,
                            ),
                          ),
                        ],
                      ]),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  void _shareBackup() {
    if (_sk == null || !mounted) return;
    final ws = context.read<WalletService>();
    final wallet = ws.activeWallet;
    final backup = jsonEncode({
      'name': wallet?.name ?? '',
      'address': wallet?.address ?? '',
      'private_key': _sk,
      'export_date': DateTime.now().toIso8601String(),
    });

    // On desktop, offer "Save to file" instead of share sheet
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      _saveBackupToFile(backup);
    } else {
      Share.share(backup, subject: 'Octopus Wallet Backup');
    }
  }

  Future<void> _saveBackupToFile(String backup) async {
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Wallet Backup',
        fileName: 'octopus_wallet_backup.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result != null && mounted) {
        await File(result).writeAsString(backup);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Backup saved successfully')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }
}

class _InfoBox extends StatelessWidget {
  final String label;
  final String value;
  final bool monospace;
  final bool canCopy;
  final String? copyValue;

  const _InfoBox({
    required this.label,
    required this.value,
    this.monospace = false,
    this.canCopy = false,
    this.copyValue,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text('$label:',
                  style: TextStyle(
                      color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
            ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: monospace ? 'monospace' : null,
                fontSize: 12,
              ),
            ),
          ),
          if (canCopy)
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: copyValue ?? value));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Copied to clipboard'),
                      duration: Duration(seconds: 2)),
                );
              },
            ),
        ],
      ),
    );
  }
}
