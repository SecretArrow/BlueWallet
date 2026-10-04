import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../services/wallet_service.dart';
import '../../../services/network_service.dart';
import '../../../models/token_balance.dart';
import '../../../widgets/octopus_card.dart';
import '../../../widgets/tonal_button.dart';
import '../../../widgets/adaptive_body.dart';
import '../../../widgets/shimmer_placeholder.dart';

/// Dashboard tab — wallet selector, address, balances, token list.
///
/// On first mount it always triggers a background network refresh so the user
/// sees fresh data without needing to pull-to-refresh.  Cached values from
/// SQLite are shown instantly while the network call is in flight.
class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _firstLoadTriggered = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(
        () => setState(() => _query = _searchCtrl.text.toLowerCase()));
    // Schedule initial network load after first frame so providers are ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_firstLoadTriggered) {
        _firstLoadTriggered = true;
        _reload();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    final ws = context.read<WalletService>();
    final ns = context.read<NetworkService>();
    try {
      await ws.refresh(ns.activeNodeUrl);
      if (!mounted) return;
      await ws.fetchTokens(ns.activeNodeUrl);
      if (ws.errorMessage != null && mounted) {
        throw Exception(ws.errorMessage);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Network error: $e'),
        action: SnackBarAction(label: 'Retry', onPressed: _reload),
        duration: const Duration(hours: 1), // Indefinite
      ));
    }
  }

  List<TokenBalance> _filtered(List<TokenBalance> all) => _query.isEmpty
      ? all
      : all
          .where((t) =>
              t.symbol.toLowerCase().contains(_query) ||
              t.name.toLowerCase().contains(_query))
          .toList();

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WalletService>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return AdaptiveBody(
      child: RefreshIndicator(
        color: cs.primary,
        onRefresh: () async {
          final ns = context.read<NetworkService>();
          await ws.refresh(ns.activeNodeUrl);
          if (context.mounted) await ws.loadHistory(ns.activeNodeUrl);
          if (context.mounted) await ws.fetchTokens(ns.activeNodeUrl);
        },
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Wallet selector
                  _WalletSelectorCard(ws: ws),
                  const SizedBox(height: 12),
                  // Balance card
                  _BalanceCard(ws: ws, cs: cs, tt: tt),
                  const SizedBox(height: 14),
                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: TonalButton(
                          label: 'Send',
                          icon: Icons.send_rounded,
                          onPressed: () => context.push('/send-menu'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TonalButton(
                          label: 'Receive',
                          icon: Icons.qr_code_rounded,
                          onPressed: () => context.push('/receive'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // Token list header
                  Row(
                    children: [
                      Text('Token Balances', style: tt.headlineSmall),
                      const Spacer(),
                      SizedBox(
                        width: 160,
                        height: 36,
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText: 'Search...',
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: cs.surfaceContainerHighest,
                            hintStyle: TextStyle(
                                color: cs.onSurfaceVariant, fontSize: 12),
                          ),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ]),
              ),
            ),
            // Token list
            if (ws.loading && ws.tokens.isEmpty)
              const SliverFillRemaining(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      ShimmerPlaceholder(width: double.infinity, height: 72),
                      SizedBox(height: 10),
                      ShimmerPlaceholder(width: double.infinity, height: 72),
                      SizedBox(height: 10),
                      ShimmerPlaceholder(width: double.infinity, height: 72),
                    ],
                  ),
                ),
              )
            else if (ws.tokens.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.all(32),
                sliver: SliverToBoxAdapter(
                  child: Center(child: _TokenEmptyState(ws: ws)),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final tokens = _filtered(ws.tokens);
                      if (i >= tokens.length) return null;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _TokenItem(token: tokens[i]),
                      );
                    },
                    childCount: _filtered(ws.tokens).length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WalletSelectorCard extends StatelessWidget {
  final WalletService ws;
  const _WalletSelectorCard({required this.ws});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (ws.wallets.isEmpty) {
      return OctopusCard(
        child: Text('No wallets', style: TextStyle(color: cs.onSurfaceVariant)),
      );
    }
    return OctopusCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: ws.activeWallet?.id,
          isExpanded: true,
          dropdownColor: cs.surface,
          style: TextStyle(color: cs.onSurface, fontSize: 14),
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: cs.primary),
          items: ws.wallets
              .map((w) => DropdownMenuItem(
                    value: w.id,
                    child: Text(w.name, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (id) {
            if (id != null) ws.setActiveWallet(id);
          },
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final WalletService ws;
  final ColorScheme cs;
  final TextTheme tt;

  const _BalanceCard({required this.ws, required this.cs, required this.tt});

  @override
  Widget build(BuildContext context) {
    final address = ws.activeWallet?.address ?? 'Loading wallet…';

    // Display encrypted balance with status indicator
    // Show decrypted amount if available, otherwise show encrypted status
    String encDisplay;
    IconData encIcon;
    Color? encColor;

    if (ws.encryptedBalanceRaw > 0) {
      // Successfully decrypted
      encDisplay = '${ws.encryptedBalance} OCT';
      encIcon = Icons.enhanced_encryption_outlined;
      encColor = cs.secondary;
    } else if (ws.encryptedBalanceCipher != null &&
        ws.encryptedBalanceCipher!.isNotEmpty &&
        ws.encryptedBalanceCipher != '0') {
      // Has encrypted data but not decrypted (PVAC may not be initialized)
      encDisplay = 'Encrypted (tap to decrypt)';
      encIcon = Icons.lock_outline_rounded;
      encColor = cs.onSurfaceVariant;
    } else {
      // No encrypted balance
      encDisplay = '${ws.encryptedBalance} OCT';
      encIcon = Icons.enhanced_encryption_outlined;
      encColor = cs.onSurfaceVariant;
    }

    return OctopusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Address row — tap to copy ──────────────────────────────────
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              Clipboard.setData(ClipboardData(text: address));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Address copied'),
                    duration: Duration(seconds: 2)),
              );
              Future.delayed(const Duration(seconds: 30), () {
                Clipboard.setData(const ClipboardData(text: ''));
              });
            },
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    address,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                    softWrap: true,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.copy_rounded, size: 14, color: cs.primary),
              ],
            ),
          ),
          const Divider(height: 16),

          // ── Total balance ─────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Balance',
                        style:
                            tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    ws.loading && ws.publicBalance == '0.000000'
                        ? const ShimmerPlaceholder(width: 120, height: 28)
                        : Text(
                            '${ws.totalBalance} OCT',
                            style: tt.titleLarge?.copyWith(
                              color: cs.primary,
                              fontSize: 20,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ],
                ),
              ),
              // Spinning indicator while network is refreshing
              if (ws.loading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: cs.primary),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Public balance ────────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('Public:',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(width: 4),
              Text(
                '${ws.publicBalance} OCT',
                style: tt.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // ── Encrypted balance ─────────────────────────────────────────
          Row(
            children: [
              Icon(encIcon, size: 14, color: encColor),
              const SizedBox(width: 6),
              Text('Encrypted:',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(width: 4),
              Text(
                encDisplay,
                style: tt.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  color: encColor,
                ),
              ),
              const Spacer(),
              // Quick-access decrypt link
              InkWell(
                onTap: () => context.push('/decrypt-balance'),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.key_rounded, size: 12, color: cs.primary),
                      const SizedBox(width: 3),
                      Text('Decrypt',
                          style: tt.bodySmall
                              ?.copyWith(color: cs.primary, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ── Error notice (connectivity) ───────────────────────────────
          if (ws.errorMessage != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 13, color: cs.error),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    ws.errorMessage!,
                    style: tt.bodySmall?.copyWith(color: cs.error),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TokenEmptyState extends StatelessWidget {
  final WalletService ws;
  const _TokenEmptyState({required this.ws});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (ws.errorMessage != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 40, color: cs.error),
          const SizedBox(height: 12),
          Text(ws.errorMessage!,
              style: tt.bodyMedium?.copyWith(color: cs.error),
              textAlign: TextAlign.center),
        ],
      );
    }

    if (ws.accountNotFound) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_balance_wallet_outlined,
              size: 48, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'No on-chain activity yet.\nFund this address to get started.',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.token_outlined,
            size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
        const SizedBox(height: 12),
        Text('No token balances found.',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text('OCS01 tokens with a non-zero balance will appear here.',
            style: tt.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
            textAlign: TextAlign.center),
      ],
    );
  }
}

class _TokenItem extends StatelessWidget {
  final TokenBalance token;
  const _TokenItem({required this.token});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: () => context.push('/token-transfer', extra: {
        'tokenAddress': token.address,
        'tokenSymbol': token.symbol,
        'tokenName': token.name,
      }),
      child: OctopusCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Symbol avatar
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: cs.primary.withValues(alpha: 0.25), width: 1),
              ),
              child: Center(
                child: Text(
                  token.symbol.length <= 4
                      ? token.symbol
                      : token.symbol.substring(0, 4),
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: token.symbol.length <= 3 ? 12 : 9,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Token name + contract address
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(token.name,
                      style:
                          tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    token.address,
                    style: tt.bodySmall?.copyWith(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Balance + symbol stacked
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  token.balance,
                  style: tt.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
                Text(
                  token.symbol,
                  style: tt.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
