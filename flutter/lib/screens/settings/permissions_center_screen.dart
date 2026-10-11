import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/dapp/dapp_session_store.dart';
import '../../services/recent_sites_service.dart';
import '../../widgets/octopus_card.dart';

/// Permissions Center — device permissions plus dApp site sessions.
///
/// The dApp section lists per-origin grants from [DappSessionStore] with
/// one-tap revoke, and a clear-browsing-data action that wipes recent
/// sites (Startpage history) alongside cached browsing state.
class PermissionsCenterScreen extends StatefulWidget {
  const PermissionsCenterScreen({super.key});

  @override
  State<PermissionsCenterScreen> createState() =>
      _PermissionsCenterScreenState();
}

class _PermissionsCenterScreenState extends State<PermissionsCenterScreen> {
  bool _camera = false;
  bool _biometric = false;
  bool _notifications = false;
  bool _storage = false;
  bool _busy = false;

  final DappSessionStore _sessions = DappSessionStore.instance;

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    _sessions.load();
    _sessions.addListener(_onSessions);
  }

  void _onSessions() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sessions.removeListener(_onSessions);
    super.dispose();
  }

  Future<void> _clearBrowsingData() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear browsing data?'),
        content: const Text(
            'Deletes recently visited sites shown on the browser Startpage. '
            'Connected-site approvals are kept — revoke those separately.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await RecentSitesService.instance.clearAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Browsing data cleared')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sessions = _sessions.sessions;

    return Scaffold(
      appBar: AppBar(title: const Text('Permissions Center')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Manage which permissions the app uses.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
            const SizedBox(height: 16),
            if (_isMobile) ...[
              _PermissionTile(
                icon: Icons.camera_alt_rounded,
                title: 'Camera',
                subtitle: 'Required for QR code scanning',
                value: _camera,
                onChanged: (v) => setState(() => _camera = v),
              ),
              const SizedBox(height: 8),
              _PermissionTile(
                icon: Icons.fingerprint_rounded,
                title: 'Biometrics',
                subtitle: 'Use fingerprint or face to unlock',
                value: _biometric,
                onChanged: (v) => setState(() => _biometric = v),
              ),
              const SizedBox(height: 8),
            ],
            _PermissionTile(
              icon: Icons.notifications_rounded,
              title: 'Notifications',
              subtitle: 'Receive transaction alerts',
              value: _notifications,
              onChanged: (v) => setState(() => _notifications = v),
            ),
            const SizedBox(height: 8),
            _PermissionTile(
              icon: Icons.folder_rounded,
              title: 'Storage',
              subtitle: 'Import/export wallet files',
              value: _storage,
              onChanged: (v) => setState(() => _storage = v),
            ),
            const SizedBox(height: 24),
            Text('Connected sites (${sessions.length})',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (sessions.isEmpty)
              Text('No dApp has access to your wallet.',
                  style:
                      TextStyle(color: cs.onSurfaceVariant, fontSize: 13))
            else
              ...sessions.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OctopusCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(s.origin,
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () async {
                                    setState(() => _busy = true);
                                    try {
                                      await _sessions.revoke(s.origin);
                                    } finally {
                                      if (mounted) {
                                        setState(() => _busy = false);
                                      }
                                    }
                                  },
                            child: const Text('Revoke'),
                          ),
                        ],
                      ),
                    ),
                  )),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : _clearBrowsingData,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('Clear browsing data'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return OctopusCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (value ? cs.primary : cs.onSurfaceVariant)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon,
                size: 20,
                color: value ? cs.primary : cs.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style:
                        TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
