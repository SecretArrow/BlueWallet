import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings tab — matches Android MainActivity settings view exactly:
/// flat rows with 44dp circle icon, title only, bottom divider.
/// Items sorted alphabetically, then About + Logout at bottom.
/// Dev Tools visible only on desktop (Linux / Windows / macOS).
class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  static bool get _isDesktop =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  @override
  Widget build(BuildContext context) {
    final items = [
      // Sorted alphabetically (same as Android)
      _Item('Address Book', Icons.import_contacts_rounded, '/address-book'),
      _Item('Auto Scan', Icons.radar_rounded, '/auto-scan'),
      _Item('Biometric', Icons.fingerprint_rounded, '/biometric-settings'),
      _Item('Cache', Icons.storage_rounded, null,
          onTap: (ctx) => _clearCache(ctx)),
      _Item('Change PIN', Icons.pin_rounded, '/change-pin'),
      _Item('Data Usage', Icons.data_usage_rounded, '/data-usage'),
      _Item('DApp Browser', Icons.web_rounded, '/dapp-browser'),
      _Item('DApp Origins', Icons.language_rounded, '/dapp-origins'),
      if (_isDesktop)
        _Item('Developer Tools', Icons.code_rounded, '/dev-tools'),
      _Item('Local Web Server', Icons.dns_rounded, '/local-web-server-settings'),
      _Item('Networks', Icons.public_rounded, '/network-settings'),
      _Item('Polling Settings', Icons.history_rounded, '/polling-settings'),
      _Item('Permissions', Icons.notifications_rounded, '/permissions-center'),
      _Item('Session', Icons.timer_rounded, '/session-lock'),
      _Item('Theme', Icons.palette_rounded, '/theme-palette'),
      _Item('Tor Proxy', Icons.security_rounded, '/tor-proxy'),
      _Item('Wallets', Icons.account_balance_wallet_rounded, '/wallets'),
      // Always at bottom
      _Item('About', Icons.info_rounded, '/about'),
      _Item('Logout', Icons.logout_rounded, null,
          onTap: (ctx) => _doLogout(ctx), isLogout: true),
    ];

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: items.length,
      itemBuilder: (context, i) => _SettingsRow(item: items[i]),
    );
  }

  static void _clearCache(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Cache'),
        content: const Text(
            'This will clear cached balance and transaction history.\nYour wallet keys are safe.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final keys =
        prefs.getKeys().where((k) => k.startsWith('tx_history_')).toList();
    for (final k in keys) await prefs.remove(k);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cache cleared')),
      );
    }
  }

  static void _doLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text(
            'Lock your wallet session. You will need your PIN to re-enter.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Logout')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    context.go('/pin?mode=unlock');
  }
}

class _Item {
  final String title;
  final IconData icon;
  final String? route;
  final void Function(BuildContext)? onTap;
  final bool isLogout;

  const _Item(this.title, this.icon, this.route,
      {this.onTap, this.isLogout = false});
}

class _SettingsRow extends StatelessWidget {
  final _Item item;
  const _SettingsRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    void handleTap() {
      if (item.onTap != null) {
        item.onTap!(context);
      } else if (item.route != null) {
        context.push(item.route!);
      }
    }

    return Column(
      children: [
        InkWell(
          onTap: handleTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // 44dp circle icon (matches bg_settings_icon_circle)
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: item.isLogout
                        ? cs.error.withOpacity(0.12)
                        : cs.primary.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    item.icon,
                    color: item.isLogout ? cs.error : cs.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 15,
                      color: item.isLogout ? cs.error : cs.onSurface,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: cs.onSurfaceVariant, size: 20),
              ],
            ),
          ),
        ),
        // Bottom divider indented from icon (matches item_settings_action.xml)
        Divider(
          height: 1,
          indent: 76,
          endIndent: 0,
          color: cs.onSurface.withOpacity(0.08),
        ),
      ],
    );
  }
}
