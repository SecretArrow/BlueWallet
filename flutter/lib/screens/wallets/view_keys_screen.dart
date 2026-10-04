import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/wallet_service.dart';
import '../../models/wallet_profile.dart';
import '../../widgets/octopus_card.dart';
import '../../widgets/tonal_button.dart';

/// View private key and address.  Matches ViewKeysActivity.
class ViewKeysScreen extends StatefulWidget {
  final String? walletId;
  const ViewKeysScreen({super.key, this.walletId});

  @override
  State<ViewKeysScreen> createState() => _ViewKeysScreenState();
}

class _ViewKeysScreenState extends State<ViewKeysScreen> {
  String? _privateKey;
  String? _mnemonic;
  bool _revealed = false;
  bool _mnemonicRevealed = false;
  bool _loading = false;
  bool _loadingMnemonic = false;

  Future<void> _revealKey() async {
    setState(() => _loading = true);
    final ws = context.read<WalletService>();
    final id = widget.walletId ?? ws.activeWallet?.id;
    if (id == null) return;
    final pk = await ws.getPrivateKey(id);
    setState(() {
      _privateKey = pk ?? 'Key not found';
      _revealed = true;
      _loading = false;
    });
  }

  Future<void> _revealMnemonic() async {
    if (_mnemonic != null) {
      setState(() => _mnemonicRevealed = !_mnemonicRevealed);
      return;
    }
    setState(() => _loadingMnemonic = true);
    final ws = context.read<WalletService>();
    final wallet = widget.walletId != null
        ? ws.wallets.where((w) => w.id == widget.walletId).firstOrNull
        : ws.activeWallet;
    if (wallet == null) {
      setState(() => _loadingMnemonic = false);
      return;
    }

    // For child wallets, read mnemonic from the parent
    final mnemonicId = wallet.parentId ?? wallet.id;
    final m = await ws.getMnemonic(mnemonicId);
    setState(() {
      _mnemonic = m;
      _mnemonicRevealed = true;
      _loadingMnemonic = false;
    });
  }

  void _copy(BuildContext ctx, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
          content: Text('$label copied'), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _showRenameDialog(BuildContext context, WalletProfile? wallet) async {
    if (wallet == null) return;
    final controller = TextEditingController(text: wallet.name);
    final ws = context.read<WalletService>();

    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Wallet'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Wallet Name',
            hintText: 'Enter new name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                final ok = await ws.renameWallet(wallet.id, newName);
                if (ok) {
                  if (mounted) Navigator.pop(context, true);
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Name already exists or invalid')),
                    );
                  }
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WalletService>();
    final cs = Theme.of(context).colorScheme;
    final wallet = widget.walletId != null
        ? ws.wallets.where((w) => w.id == widget.walletId).firstOrNull
        : ws.activeWallet;
    final address = wallet?.address ?? '';
    final name = wallet?.name ?? '';
    final hasMnemonic = wallet?.isMnemonicWallet ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('View Keys')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
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
                  Icon(Icons.warning_rounded,
                      color: cs.onErrorContainer, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Never share your private key or seed phrase with anyone. '
                      'Anyone who has it has full control of your wallet.',
                      style:
                          TextStyle(color: cs.onErrorContainer, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Wallet name with edit button
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.edit_rounded, color: cs.primary, size: 20),
                  onPressed: () => _showRenameDialog(context, wallet),
                  tooltip: 'Rename Wallet',
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Address card
            _KeyCard(
              label: 'Public Address',
              value: address,
              onCopy: () => _copy(context, address, 'Address'),
            ),
            const SizedBox(height: 12),

            // Private key
            if (!_revealed) ...[
              OctopusCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Private Key',
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 12)),
                    const SizedBox(height: 10),
                    TonalButton(
                      label: 'Reveal Private Key',
                      icon: Icons.visibility_rounded,
                      loading: _loading,
                      onPressed: _loading ? null : _revealKey,
                    ),
                  ],
                ),
              ),
            ] else ...[
              _KeyCard(
                label: 'Private Key (Base64)',
                value: _privateKey ?? '',
                sensitive: true,
                onCopy: () => _copy(context, _privateKey ?? '', 'Private key'),
              ),
            ],

            // Seed Phrase — only for mnemonic wallets
            if (hasMnemonic) ...[
              const SizedBox(height: 12),
              OctopusCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Seed Phrase (12 Words)',
                                  style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 12)),
                              if (wallet?.derivationPath != null) ...[
                                const SizedBox(height: 2),
                                Text(wallet!.derivationPath!,
                                    style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 10,
                                        color: cs.onSurfaceVariant)),
                              ],
                            ],
                          ),
                        ),
                        if (_mnemonic != null)
                          IconButton(
                            icon: Icon(
                              _mnemonicRevealed
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              size: 18,
                              color: cs.primary,
                            ),
                            onPressed: _revealMnemonic,
                            tooltip: _mnemonicRevealed
                                ? 'Hide seed phrase'
                                : 'Show seed phrase',
                          ),
                        if (_mnemonic != null)
                          IconButton(
                            icon: Icon(Icons.copy, size: 18, color: cs.primary),
                            onPressed: () =>
                                _copy(context, _mnemonic!, 'Seed phrase'),
                            tooltip: 'Copy seed phrase',
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (!_mnemonicRevealed || _mnemonic == null) ...[
                      TonalButton(
                        label: 'Reveal Seed Phrase',
                        icon: Icons.lock_open_rounded,
                        loading: _loadingMnemonic,
                        onPressed: _loadingMnemonic ? null : _revealMnemonic,
                      ),
                    ] else ...[
                      _MnemonicGrid(words: _mnemonic!.split(' ')),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.account_tree_rounded),
                label: const Text('Derive Child Wallet'),
                onPressed: () {
                  final id = wallet?.id ?? '';
                  context.push('/derive-child-wallet', extra: id);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Displays mnemonic words in a responsive 3-column grid.
class _MnemonicGrid extends StatelessWidget {
  final List<String> words;
  const _MnemonicGrid({required this.words});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    for (int i = 0; i < words.length; i += 3) {
      final rowChildren = <Widget>[];
      for (int j = i; j < i + 3 && j < words.length; j++) {
        rowChildren.add(Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Text('${j + 1}.',
                      style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
                          fontFamily: 'monospace')),
                  const SizedBox(width: 4),
                  Text(words[j],
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12)),
                ],
              ),
            ),
          ),
        ));
      }
      rows.add(Row(children: rowChildren));
    }
    return Column(children: rows);
  }
}

class _KeyCard extends StatelessWidget {
  final String label;
  final String value;
  final bool sensitive;
  final VoidCallback onCopy;

  const _KeyCard({
    required this.label,
    required this.value,
    this.sensitive = false,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return OctopusCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              ),
              IconButton(
                icon: Icon(Icons.copy, size: 18, color: cs.primary),
                onPressed: onCopy,
                tooltip: 'Copy',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: sensitive ? cs.error : cs.onSurface,
              wordSpacing: 2,
            ),
            softWrap: true,
          ),
        ],
      ),
    );
  }
}
