import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/backup_reminder.dart';
import '../../services/wallet_service.dart';
import '../../models/wallet_profile.dart';
import '../../widgets/octopus_card.dart';
import '../../widgets/tonal_button.dart';

/// Wallets management — list, switch, delete.  Matches WalletsActivity.
class WalletsScreen extends StatelessWidget {
  const WalletsScreen({super.key});

  static String _maskAddr(String addr) {
    if (addr.length <= 20) return addr;
    return '${addr.substring(0, 8)}...${addr.substring(addr.length - 8)}';
  }

  /// Mnemonic ROOT wallet ids (children resolve to their parent's seed).
  static List<String> _mnemonicRootIds(WalletService ws) {
    final ids = <String>{};
    for (final w in ws.wallets) {
      if (w.isMnemonicWallet) ids.add(w.parentId ?? w.id);
    }
    return ids.toList();
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WalletService>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Wallets')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/add-wallet'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Account'),
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: ws.wallets.isEmpty
            ? Center(
                child: Text(
                  'No wallets found',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: ws.wallets.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  // Reminder banner sits above the wallet list.
                  if (i == 0) {
                    return _BackupReminderBanner(
                      mnemonicWalletIds: _mnemonicRootIds(ws),
                    );
                  }
                  final w = ws.wallets[i - 1];
                  final isActive = w.id == ws.activeWallet?.id;
                  return _WalletTile(
                    wallet: w,
                    isActive: isActive,
                    canDelete: ws.wallets.length > 1,
                    maskAddr: _maskAddr,
                    onActivate: () => ws.setActiveWallet(w.id),
                    onViewKeys: () => context.push('/view-keys?id=${w.id}'),
                    onExport: () => context.push('/export-wallet?id=${w.id}'),
                    onDelete: () => _confirmDelete(context, ws, w),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WalletService ws, WalletProfile wallet) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Wallet'),
        content: Text(
          'Are you sure you want to remove "${wallet.name}"? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ws.removeWallet(wallet.id);
    }
  }
}

class _WalletTile extends StatelessWidget {
  final WalletProfile wallet;
  final bool isActive;
  final bool canDelete;
  final String Function(String) maskAddr;
  final VoidCallback onActivate;
  final VoidCallback onViewKeys;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  const _WalletTile({
    required this.wallet,
    required this.isActive,
    required this.canDelete,
    required this.maskAddr,
    required this.onActivate,
    required this.onViewKeys,
    required this.onExport,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return OctopusCard(
      onTap: onActivate,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isActive
                  ? cs.primary.withValues(alpha: 0.15)
                  : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              border: isActive
                  ? Border.all(color: cs.primary.withValues(alpha: 0.5))
                  : null,
            ),
            child: Icon(
              wallet.watchOnly
                  ? Icons.visibility_outlined
                  : Icons.account_balance_wallet_rounded,
              color: isActive ? cs.primary : cs.onSurfaceVariant,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(wallet.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (wallet.watchOnly) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.secondary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.visibility_outlined,
                                size: 10, color: cs.secondary),
                            const SizedBox(width: 3),
                            Text(
                              'WATCH-ONLY',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: cs.secondary,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (isActive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'ACTIVE',
                          style: TextStyle(
                              fontSize: 9,
                              color: cs.primary,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  maskAddr(wallet.address),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Three-dot popup menu
          PopupMenuButton<_WalletAction>(
            icon: Icon(Icons.more_vert_rounded,
                color: cs.onSurfaceVariant, size: 20),
            tooltip: 'Wallet options',
            onSelected: (action) {
              switch (action) {
                case _WalletAction.activate:
                  onActivate();
                case _WalletAction.viewKeys:
                  onViewKeys();
                case _WalletAction.export:
                  onExport();
                case _WalletAction.delete:
                  onDelete();
              }
            },
            itemBuilder: (_) => [
              if (!isActive)
                const PopupMenuItem(
                  value: _WalletAction.activate,
                  child: Row(children: [
                    Icon(Icons.check_circle_outline_rounded, size: 18),
                    SizedBox(width: 10),
                    Text('Set Active'),
                  ]),
                ),
              const PopupMenuItem(
                value: _WalletAction.viewKeys,
                child: Row(children: [
                  Icon(Icons.visibility_outlined, size: 18),
                  SizedBox(width: 10),
                  Text('View Keys'),
                ]),
              ),
              const PopupMenuItem(
                value: _WalletAction.export,
                child: Row(children: [
                  Icon(Icons.upload_rounded, size: 18),
                  SizedBox(width: 10),
                  Text('Export Wallet'),
                ]),
              ),
              if (canDelete)
                PopupMenuItem(
                  value: _WalletAction.delete,
                  child: Row(children: [
                    Icon(Icons.delete_outline_rounded,
                        size: 18, color: cs.error),
                    const SizedBox(width: 10),
                    Text('Delete', style: TextStyle(color: cs.error)),
                  ]),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _WalletAction { activate, viewKeys, export, delete }

/// Dismissible backup-reminder banner shown above the wallet list.
///
/// Visible only while [BackupReminder.shouldRemind] is true (due and not
/// snoozed). [Dismiss] hides it for this session only; "Snooze 7 Days"
/// persists via [BackupReminder.snooze]; "Verify Now" opens the quiz and
/// the banner re-checks itself when the user returns.
class _BackupReminderBanner extends StatefulWidget {
  final List<String> mnemonicWalletIds;
  const _BackupReminderBanner({required this.mnemonicWalletIds});

  @override
  State<_BackupReminderBanner> createState() => _BackupReminderBannerState();
}

class _BackupReminderBannerState extends State<_BackupReminderBanner> {
  bool _visible = true;
  bool? _due;
  bool _snoozing = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(_BackupReminderBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Wallet list changed (added/removed) → re-evaluate the reminder.
    _check();
  }

  Future<void> _check() async {
    final due = await BackupReminder.shouldRemind(
      DateTime.now(),
      mnemonicWalletIds: widget.mnemonicWalletIds,
    );
    if (mounted) setState(() => _due = due);
  }

  Future<void> _snooze() async {
    if (_snoozing) return;
    setState(() => _snoozing = true);
    await BackupReminder.snooze(DateTime.now());
    if (mounted) {
      setState(() {
        _visible = false;
        _snoozing = false;
      });
    }
  }

  Future<void> _verifyNow() async {
    await context.push('/verify-backup');
    // Re-check when returning — a successful verification hides the banner.
    _check();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible || _due != true) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined,
                  color: cs.onPrimaryContainer, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Verify your recovery phrase backup',
                  style: TextStyle(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                      fontSize: 14),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded,
                    size: 18, color: cs.onPrimaryContainer),
                tooltip: 'Dismiss',
                onPressed: () => setState(() => _visible = false),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'It has been a while since your seed phrase backup was last '
            'verified. Take the word quiz to confirm your backup works.',
            style: TextStyle(color: cs.onPrimaryContainer, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TonalButton(
                  label: 'Verify Now',
                  icon: Icons.task_alt_rounded,
                  onPressed: _verifyNow,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TonalButton(
                  label: 'Snooze 7 Days',
                  loading: _snoozing,
                  onPressed: _snoozing ? null : _snooze,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
