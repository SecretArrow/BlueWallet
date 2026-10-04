import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/adaptive_body.dart';

/// Dev Tools hub — desktop-only menu listing smart contract operations.
/// Guarded: redirects to home on mobile platforms.
class DevToolsScreen extends StatelessWidget {
  const DevToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!(Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/home');
      });
      return const Scaffold(body: Center(child: Text('Desktop only')));
    }

    final items = [
      _DevItem(
        icon: Icons.publish_rounded,
        title: 'Deploy Contract',
        subtitle: 'Deploy a compiled smart contract to the network',
        route: '/dev-deploy',
      ),
      _DevItem(
        icon: Icons.call_made_rounded,
        title: 'Call Contract',
        subtitle: 'Execute a state-changing contract function',
        route: '/dev-call',
      ),
      _DevItem(
        icon: Icons.visibility_rounded,
        title: 'View Contract',
        subtitle: 'Read-only call to a contract function',
        route: '/dev-view',
      ),
      _DevItem(
        icon: Icons.info_outlined,
        title: 'Contract Info',
        subtitle: 'Get ABI, storage, and metadata for a contract',
        route: '/dev-info',
      ),
      _DevItem(
        icon: Icons.receipt_long_rounded,
        title: 'Transaction Receipt',
        subtitle: 'Fetch the receipt for a completed transaction',
        route: '/dev-receipt',
      ),
      _DevItem(
        icon: Icons.verified_rounded,
        title: 'Verify Contract',
        subtitle: 'Submit source code to verify a deployed contract',
        route: '/dev-verify',
      ),
      _DevItem(
        icon: Icons.storage_rounded,
        title: 'Contract Storage',
        subtitle: 'Read a raw storage slot from a contract',
        route: '/dev-storage',
      ),
      _DevItem(
        icon: Icons.calculate_rounded,
        title: 'Compute Address',
        subtitle: 'Predict a contract address from deployer + nonce',
        route: '/dev-compute-addr',
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Developer Tools')),
      body: AdaptiveBody(
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _DevCard(item: items[i]),
        ),
      ),
    );
  }
}

class _DevItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  const _DevItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });
}

class _DevCard extends StatelessWidget {
  final _DevItem item;
  const _DevCard({required this.item});

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
              Icon(item.icon, size: 28, color: cs.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 3),
                    Text(item.subtitle,
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
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
