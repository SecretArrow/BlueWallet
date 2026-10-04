import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../models/wallet_profile.dart';
import '../../services/mnemonic_service.dart';
import '../../services/wallet_service.dart';
import '../../widgets/octopus_card.dart';
import '../../widgets/tonal_button.dart';

/// Derives a child wallet from an existing mnemonic wallet at a given index.
///
/// The parent mnemonic is read from secure storage — no user input required.
/// The derivation path replaces the last component of the parent's path with
/// the user-supplied index (e.g. m/44'/540'/0'/0'/3').
class DeriveChildWalletScreen extends StatefulWidget {
  /// The parent wallet ID (mnemonic root or child).
  final String parentId;
  const DeriveChildWalletScreen({super.key, required this.parentId});

  @override
  State<DeriveChildWalletScreen> createState() =>
      _DeriveChildWalletScreenState();
}

class _DeriveChildWalletScreenState extends State<DeriveChildWalletScreen> {
  final _nameCtrl = TextEditingController();
  final _indexCtrl = TextEditingController();

  String? _previewAddress;
  String? _fullPath;
  bool _previewing = false;
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _indexCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  int? _parseIndex() {
    final s = _indexCtrl.text.trim();
    if (s.isEmpty) {
      setState(() => _error = 'Enter a derivation index');
      return null;
    }
    final n = int.tryParse(s);
    if (n == null || n < 0) {
      setState(() => _error = 'Index must be a non-negative integer');
      return null;
    }
    return n;
  }

  String _buildPath(WalletProfile parent, int index) {
    final base = _basePath(parent.derivationPath ?? "m/44'/540'/0'/0'");
    return "$base/$index'";
  }

  String _basePath(String full) {
    final idx = full.lastIndexOf('/');
    if (idx <= 1) return "m/44'/540'/0'/0'";
    return full.substring(0, idx);
  }

  // ── Preview ────────────────────────────────────────────────────────────────

  Future<void> _doPreview() async {
    final index = _parseIndex();
    if (index == null) return;

    final ws = context.read<WalletService>();
    final parent = ws.wallets.firstWhere(
      (w) => w.id == widget.parentId,
      orElse: () => throw Exception('Parent wallet not found'),
    );
    final mnemonicId = parent.parentId ?? parent.id;
    final mnemonic = await ws.getMnemonic(mnemonicId);
    if (mnemonic == null) {
      setState(() => _error = 'Mnemonic not found for this wallet.');
      return;
    }

    final path = _buildPath(parent, index);
    setState(() {
      _previewing = true;
      _error = null;
      _fullPath = path;
    });
    try {
      final kp = MnemonicService.deriveKeypair(mnemonic: mnemonic, path: path);
      setState(() {
        _previewAddress = kp['address'];
        _previewing = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Preview failed: $e';
        _previewing = false;
      });
    }
  }

  // ── Create ─────────────────────────────────────────────────────────────────

  Future<void> _doCreate() async {
    final index = _parseIndex();
    if (index == null) return;

    final ws = context.read<WalletService>();
    final name = _nameCtrl.text.trim();
    final resolvedName = name.isEmpty ? 'HD Index $index' : name;

    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      await ws.deriveChildWallet(
        parentId: widget.parentId,
        name: resolvedName,
        index: index,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$resolvedName derived!')),
        );
        context.pop();
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _creating = false;
      });
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WalletService>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final parent = ws.wallets.where((w) => w.id == widget.parentId).firstOrNull;
    final parentName = parent?.name ?? widget.parentId;
    final parentPath = parent?.derivationPath ?? "m/44'/540'/0'/0'/0'";

    return Scaffold(
      appBar: AppBar(title: const Text('Derive Child Wallet')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Info ───────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.account_tree_rounded,
                      color: cs.onPrimaryContainer, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Derive a new wallet from the same seed phrase at a '
                      'different index. The mnemonic is not re-entered — '
                      'it is read from secure storage.',
                      style:
                          TextStyle(color: cs.onPrimaryContainer, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Parent info ─────────────────────────────────────────────
            OctopusCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Parent Wallet',
                      style:
                          tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Text(parentName,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('Base path: $parentPath',
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Wallet name ─────────────────────────────────────────────
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Child Wallet Name (optional)',
                hintText: 'e.g. HD Index 1',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 14),

            // ── Index input ─────────────────────────────────────────────
            TextField(
              controller: _indexCtrl,
              decoration: const InputDecoration(
                labelText: 'Derivation Index',
                hintText: 'e.g. 1',
                border: OutlineInputBorder(),
                helperText: "Last path component, hardened: index → index'",
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {
                _previewAddress = null;
              }),
            ),
            const SizedBox(height: 14),

            // ── Preview button ──────────────────────────────────────────
            TonalButton(
              label: 'Preview Address',
              icon: Icons.preview_rounded,
              loading: _previewing,
              onPressed: (_previewing || _creating) ? null : _doPreview,
            ),

            // ── Preview result ──────────────────────────────────────────
            if (_fullPath != null || _previewAddress != null) ...[
              const SizedBox(height: 14),
              OctopusCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_fullPath != null) ...[
                      Text('Full Path',
                          style: tt.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      SelectableText(
                        _fullPath!,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (_previewAddress != null) ...[
                      Text('Preview Address',
                          style: tt.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      SelectableText(
                        _previewAddress!,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            // ── Error ───────────────────────────────────────────────────
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    Text(_error!, style: TextStyle(color: cs.onErrorContainer)),
              ),
            ],

            const SizedBox(height: 20),

            // ── Derive button ───────────────────────────────────────────
            FilledButton.icon(
              icon: _creating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_circle_rounded),
              label: const Text('Derive Wallet'),
              onPressed: (_previewing || _creating) ? null : _doCreate,
            ),
          ],
        ),
      ),
    );
  }
}
