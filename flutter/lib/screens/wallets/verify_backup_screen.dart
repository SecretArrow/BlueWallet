import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../models/wallet_profile.dart';
import '../../services/backup_reminder.dart';
import '../../services/verify_backup_logic.dart';
import '../../services/wallet_service.dart';
import '../../widgets/adaptive_body.dart';
import '../../widgets/octopus_card.dart';
import '../../widgets/tonal_button.dart';

/// Seed-phrase backup verification quiz.
///
/// The mnemonic is obtained exactly like [ViewKeysScreen] does —
/// `WalletService.getMnemonic` with the parent id for child wallets. On the
/// Flutter side that path is not PIN-gated, so no unlock step is needed.
/// The phrase lives in memory only: it is never logged, never persisted and
/// never shown on this screen.
class VerifyBackupScreen extends StatefulWidget {
  final String? walletId;
  const VerifyBackupScreen({super.key, this.walletId});

  @override
  State<VerifyBackupScreen> createState() => _VerifyBackupScreenState();
}

class _VerifyBackupScreenState extends State<VerifyBackupScreen> {
  List<String> _words = const [];
  List<int> _positions = const [];
  final List<TextEditingController> _controllers = [];
  bool _loading = true;
  bool _failedAttempt = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMnemonic();
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> _loadMnemonic() async {
    final ws = context.read<WalletService>();
    var wallet = widget.walletId != null
        ? ws.wallets.where((w) => w.id == widget.walletId).firstOrNull
        : ws.activeWallet;
    if (wallet == null) {
      if (mounted) {
        setState(() {
          _error = 'Wallet not found.';
          _loading = false;
        });
      }
      return;
    }

    // Same access path as ViewKeysScreen: child wallets read the parent seed.
    var mnemonic = await ws.getMnemonic(wallet.parentId ?? wallet.id);
    // Non-null local that flow analysis can promote safely across the
    // fallback loop below (re-assigning `wallet` would cancel its promotion).
    var target = wallet;

    // When the requested wallet has no seed phrase (e.g. an imported key
    // wallet reached via Settings), fall back to the newest mnemonic wallet.
    if (mnemonic == null || mnemonic.trim().isEmpty) {
      final mnemonicWallets = ws.wallets.where((w) => w.isMnemonicWallet);
      DateTime? newest;
      WalletProfile? fallback;
      for (final w in mnemonicWallets) {
        final created = BackupReminder.walletCreatedAt(w.parentId ?? w.id);
        if (created != null && (newest == null || created.isAfter(newest))) {
          newest = created;
          fallback = w;
        }
      }
      if (fallback != null) {
        target = fallback;
      }
      if (target.isMnemonicWallet) {
        mnemonic = await ws.getMnemonic(target.parentId ?? target.id);
      }
    }

    if (!mounted) return;
    if (mnemonic == null || mnemonic.trim().isEmpty) {
      setState(() {
        _error = 'No seed phrase found for this wallet.';
        _loading = false;
      });
      return;
    }

    final words = mnemonic.trim().split(RegExp(r'\s+'));
    if (words.length < 2) {
      setState(() {
        _error = 'Stored seed phrase is invalid.';
        _loading = false;
      });
      return;
    }

    // Stable within a day, different across days (see VerifyBackupLogic).
    final seed = VerifyBackupLogic.seedFor(target.id, DateTime.now());
    final positions =
        VerifyBackupLogic.pickPositions(words.length, Random(seed));
    _controllers.clear();
    for (var i = 0; i < positions.length; i++) {
      _controllers.add(TextEditingController());
    }

    setState(() {
      _words = words;
      _positions = positions;
      _loading = false;
    });
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_loading || _positions.isEmpty) return;
    final answers = [for (final controller in _controllers) controller.text];
    if (answers.any((a) => a.trim().isEmpty)) {
      setState(() => _error = 'Please fill in every word.');
      return;
    }

    if (VerifyBackupLogic.answersMatch(_words, _positions, answers)) {
      await BackupReminder.markVerified(DateTime.now());
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Backup Verified'),
          content: const Text(
              'Your recovery phrase backup is confirmed.\n'
              'You will be reminded again in 30 days.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) context.pop();
      return;
    }

    setState(() {
      _failedAttempt = true;
      _error = 'One or more words are incorrect. '
          'Check your written backup and try again.';
    });
  }

  void _retry() {
    for (final controller in _controllers) {
      controller.clear();
    }
    setState(() => _error = null);
  }

  void _viewRecoveryPhrase() {
    // Reuse the existing reveal flow (ViewKeysScreen) for a failed attempt.
    final ws = context.read<WalletService>();
    final id = widget.walletId ?? ws.activeWallet?.id;
    if (id != null && id.isNotEmpty) {
      context.push('/view-keys?id=${Uri.encodeComponent(id)}');
    } else {
      context.push('/view-keys');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Verify Backup')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : AdaptiveBody(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null && _positions.isEmpty) ...[
                      Icon(Icons.search_off_rounded,
                          size: 48, color: cs.onSurfaceVariant),
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: tt.bodyMedium
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ] else ...[
                      // ── Info banner ────────────────────────────────
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.shield_outlined,
                                color: cs.onPrimaryContainer, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Type the requested words from your recovery '
                                'phrase to confirm your backup still works.',
                                style: TextStyle(
                                    color: cs.onPrimaryContainer,
                                    fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Quiz fields ────────────────────────────────
                      for (var i = 0; i < _positions.length; i++) ...[
                        OctopusCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Word #${_positions[i]}',
                                style: tt.titleSmall?.copyWith(
                                    color: cs.primary,
                                    fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _controllers[i],
                                autocorrect: false,
                                enableSuggestions: false,
                                textCapitalization: TextCapitalization.none,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  hintText: 'Enter the word',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // ── Error ───────────────────────────────────────
                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.errorContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(_error!,
                              style: TextStyle(
                                  color: cs.onErrorContainer, fontSize: 13)),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // ── Submit ──────────────────────────────────────
                      TonalButton(
                        label: 'Verify',
                        icon: Icons.task_alt_rounded,
                        onPressed: _submit,
                      ),

                      if (_failedAttempt) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TonalButton(
                                label: 'Retry',
                                icon: Icons.refresh_rounded,
                                onPressed: _retry,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TonalButton(
                                label: 'View Phrase',
                                icon: Icons.visibility_rounded,
                                onPressed: _viewRecoveryPhrase,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
