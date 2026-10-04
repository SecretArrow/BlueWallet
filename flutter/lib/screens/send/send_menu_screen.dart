import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Send Menu — matches Android SendMenuActivity exactly:
/// 5 items with Card (elevation 1, radius 14dp), 28dp icon (no container),
/// bold title 15sp, subtitle 12sp, chevron. No header intro text.
class SendMenuScreen extends StatelessWidget {
  const SendMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      _MenuItem(
        icon: Icons.send_rounded,
        title: 'Send',
        subtitle: 'Send OCT to an address',
        route: '/send',
      ),
      _MenuItem(
        icon: Icons.visibility_off_rounded,
        title: 'Stealth Send',
        subtitle: 'Private stealth transaction',
        route: '/stealth-send',
      ),
      _MenuItem(
        icon: Icons.lock_outline_rounded,
        title: 'Encrypt Balance',
        subtitle: 'Move balance to encrypted mode',
        route: '/encrypt-balance',
      ),
      _MenuItem(
        icon: Icons.lock_open_rounded,
        title: 'Decrypt Balance',
        subtitle: 'Return encrypted balance to public',
        route: '/decrypt-balance',
      ),
      _MenuItem(
        icon: Icons.token_rounded,
        title: 'Token Transfer',
        subtitle: 'Send tokens via smart contract',
        route: '/token-transfer',
      ),
      _MenuItem(
        icon: Icons.list_alt_rounded,
        title: 'Transactions Manager',
        subtitle: 'View all queued and completed transactions',
        route: '/tx-manager',
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Menu'),
        centerTitle: true,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _MenuCard(item: items[i]),
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  const _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });
}

class _MenuCard extends StatelessWidget {
  final _MenuItem item;
  const _MenuCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () => context.push(item.route),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // 28dp icon, no container (matching Android)
              Icon(item.icon, size: 28, color: cs.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: cs.onSurfaceVariant, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
