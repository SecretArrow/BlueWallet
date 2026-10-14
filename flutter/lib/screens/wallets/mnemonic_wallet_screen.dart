import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/mnemonic_service.dart';
import '../../services/wallet_service.dart';
import '../../widgets/octopus_card.dart';
import '../../widgets/tonal_button.dart';

const String _kDefaultPath = "m/44'/540'/0'/0'/0'";

/// Screen for creating a new wallet from a BIP-39 mnemonic phrase.
///
/// Workflow:
///   1. Press [Generate] to get a random 12-word phrase (address is derived
///      and shown immediately for validation).
///   2. Optionally edit the HD derivation path.
///   3. Press [Create Now] to persist the wallet.
///   4. Copy icon lets the user copy the phrase to clipboard.
class MnemonicWalletScreen extends StatefulWidget {
  const MnemonicWalletScreen({super.key});

  @override
  State<MnemonicWalletScreen> createState() => _MnemonicWalletScreenState();
}

class _MnemonicWalletScreenState extends State<MnemonicWalletScreen> {
  final _nameCtrl = TextEditingController();
  final _pathCtrl = TextEditingController(text: _kDefaultPath);

  String _mnemonic = '';
  String _previewAddress = '';
  bool _loading = false;
  bool _creating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The previewed address is derived from the path at generate time; if
    // the user edits the path afterwards, drop the stale preview so the
    // screen never shows an address the wallet will NOT get.
    _pathCtrl.addListener(_onPathChanged);
  }

  void _onPathChanged() {
    if (_previewAddress.isEmpty) return;
    // Only react to real user edits (our own reset writes the same text).
    if (_lastSyncedPath == _pathCtrl.text) return;
    if (mounted) {
      setState(() {
        _previewAddress = '';
        _error = 'Derivation path changed — press Generate to derive the '
            'address for the new path before creating.';
      });
    }
  }

  String _lastSyncedPath = '';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pathCtrl.dispose();
    super.dispose();
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _generate() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final path = _validatedPath();
      if (path == null) {
        setState(() {
          _loading = false;
        });
        return;
      }

      // Keep regenerating until we get a valid wallet (never show failed)
      String? phrase;
      Map<String, String>? kp;
      int maxAttempts = 100; // Prevent infinite loop
      int attempts = 0;

      // Regenerate until valid address is produced
      while ((phrase == null || kp == null) && attempts < maxAttempts) {
        attempts++;
        try {
          // Generate and validate mnemonic
          final candidate = MnemonicService.generate();

          // Validate mnemonic (word list + checksum)
          if (!MnemonicService.validate(candidate)) {
            // Invalid mnemonic, regenerate
            continue;
          }

          phrase = candidate;
          kp = MnemonicService.deriveKeypair(mnemonic: phrase, path: path);

          // Validate address format
          final addr = kp['address'];
          if (addr == null ||
              addr.isEmpty ||
              addr.length != 47 ||
              !addr.startsWith('oct')) {
            // Invalid address, clear and regenerate
            phrase = null;
            kp = null;
            // Continue loop - regenerate
          }
        } catch (e) {
          // Generation failed, clear and regenerate
          phrase = null;
          kp = null;
          // Continue loop - regenerate
        }
      }

      // Check if we got a valid result. Copy to fresh locals first: `phrase`
      // and `kp` are reassigned inside the loop above, so they do not
      // promote after it — assert once here instead of `!` everywhere.
      final readyPhrase = phrase;
      final readyKp = kp;
      if (readyPhrase == null || readyKp == null) {
        if (!mounted) return;
        setState(() {
          _error =
              'Failed to generate valid wallet after multiple attempts. Please try again.';
          _loading = false;
        });
        return;
      }

      // We have a valid wallet at this point
      final address = readyKp['address']?.toString() ?? '';
      if (address.isEmpty) {
        if (!mounted) return;
        setState(() {
          _error = 'Generation produced an empty address. Please try again.';
          _loading = false;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _mnemonic = readyPhrase;
        _previewAddress = address;
        _loading = false;
      });
      _lastSyncedPath = _pathCtrl.text;
    } catch (e) {
      // This should never happen, but just in case
      if (!mounted) return;
      setState(() {
        _error = 'Generation failed: $e';
        _loading = false;
      });
    }
  }

  Future<void> _createNow() async {
    if (_mnemonic.isEmpty) {
      setState(() => _error = 'Press Generate first to create a phrase.');
      return;
    }
    final path = _validatedPath();
    if (path == null) return;

    final name = _nameCtrl.text.trim();
    final ws = context.read<WalletService>();
    final resolvedName =
        name.isEmpty ? 'HD Wallet ${ws.wallets.length + 1}' : name;

    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      await ws.createFromMnemonic(
        name: resolvedName,
        mnemonic: _mnemonic,
        path: path,
        // Freshly generated phrase: no on-chain history to detect. Skipping
        // the probe keeps the created address identical to the previewed
        // one and avoids a blocking network round-trip at create time.
        autoDetect: false,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mnemonic wallet created!')),
        );
        context.pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _creating = false;
      });
    }
  }

  void _copyPhrase() {
    if (_mnemonic.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _mnemonic));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Seed phrase copied to clipboard')),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Validates the path field. Returns the normalised path or sets _error and
  /// returns null.
  String? _validatedPath() {
    final raw = _pathCtrl.text.trim();
    try {
      return MnemonicService.normalizePath(raw);
    } catch (e) {
      setState(() => _error = 'Invalid derivation path: $e');
      return null;
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hasMnemonic = _mnemonic.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Create with Mnemonic')),
      body: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Info banner ─────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: cs.onPrimaryContainer, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Store your seed phrase safely — it cannot be recovered if lost.',
                        style: TextStyle(
                            color: cs.onPrimaryContainer, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Name input ──────────────────────────────────────────────
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Wallet Name (optional)',
                  hintText: 'e.g. My HD Wallet',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 14),

              // ── Derivation path ─────────────────────────────────────────
              TextField(
                controller: _pathCtrl,
                decoration: InputDecoration(
                  labelText: 'HD Derivation Path',
                  hintText: "m/44'/540'/0'/0'/0'",
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.restore_rounded),
                    tooltip: 'Reset to default',
                    onPressed: () => _pathCtrl.text = _kDefaultPath,
                  ),
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                "Tip: all components must be hardened (').  "
                "Common paths: m/44'/540'/0'/0'/0'  or  m/0'/0'",
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 20),

              // ── Generate button ─────────────────────────────────────────
              TonalButton(
                label: 'Generate',
                icon: Icons.shuffle_rounded,
                loading: _loading,
                onPressed: (_loading || _creating) ? null : _generate,
              ),
              const SizedBox(height: 20),

              // ── Mnemonic phrase display ─────────────────────────────────
              if (hasMnemonic) ...[
                OctopusCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.lock_outline_rounded,
                              color: cs.primary, size: 18),
                          const SizedBox(width: 8),
                          Text('Seed Phrase (12 words)',
                              style: tt.titleSmall?.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.bold)),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            tooltip: 'Copy seed phrase',
                            onPressed: _copyPhrase,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _MnemonicGrid(words: _mnemonic.split(' ')),
                      const SizedBox(height: 14),
                      const Divider(),
                      const SizedBox(height: 10),
                      Text('Derived Address',
                          style: tt.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      SelectableText(
                        _previewAddress,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Error ───────────────────────────────────────────────
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_error!,
                        style: TextStyle(color: cs.onErrorContainer)),
                  ),
                  const SizedBox(height: 12),
                ],

                // ── Create Now button ───────────────────────────────────
                TonalButton(
                  label: 'Create Now',
                  icon: Icons.check_circle_rounded,
                  loading: _creating,
                  onPressed: (_loading || _creating) ? null : _createNow,
                ),
              ] else ...[
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_error!,
                        style: TextStyle(color: cs.onErrorContainer)),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Word-grid widget ──────────────────────────────────────────────────────────

class _MnemonicGrid extends StatelessWidget {
  final List<String> words;
  const _MnemonicGrid({required this.words});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.8,
      ),
      itemCount: words.length,
      itemBuilder: (_, i) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Text(
                '${i + 1}.',
                style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  words[i],
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
