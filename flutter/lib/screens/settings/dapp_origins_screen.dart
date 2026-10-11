import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/dapp/dapp_session_store.dart';
import '../../widgets/octopus_card.dart';

/// dApp connection sessions: per-origin grants with scopes, revocable.
///
/// Sessions are created when the user approves `connect` / `requestAccounts`
/// in the dApp browser and are checked before any connected-only method.
/// Revoking here disconnects the origin immediately.
class DappOriginsScreen extends StatefulWidget {
  const DappOriginsScreen({super.key});

  @override
  State<DappOriginsScreen> createState() => _DappOriginsScreenState();
}

class _DappOriginsScreenState extends State<DappOriginsScreen> {
  final DappSessionStore _store = DappSessionStore.instance;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _store.load();
    _store.addListener(_onStore);
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    super.dispose();
  }

  Future<void> _revoke(String origin) async {
    setState(() => _busy = true);
    try {
      await _store.revoke(origin);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revokeAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect all sites?'),
        content: const Text('Every dApp will need to request access again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Disconnect all')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _store.revokeAll();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sessions = _store.sessions;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connected Sites'),
        actions: [
          if (sessions.isNotEmpty)
            TextButton(
              onPressed: _busy ? null : _revokeAll,
              child: const Text('Revoke all'),
            ),
        ],
      ),
      body: SafeArea(
        child: sessions.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.web_rounded,
                        size: 48,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                    const SizedBox(height: 12),
                    Text('No connected sites',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text(
                      'Sites you approve in the dApp browser appear here.',
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: sessions.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final s = sessions[i];
                  return OctopusCard(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check_rounded,
                              size: 18, color: Colors.green),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                s.origin,
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 12),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_short(s.address)} · ${s.scopes.join(', ')}',
                                style: TextStyle(
                                    fontSize: 11, color: cs.onSurfaceVariant),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          tooltip: 'Copy origin',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: s.origin));
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Origin copied')));
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline_rounded,
                              size: 18, color: cs.error),
                          tooltip: 'Revoke access',
                          onPressed: _busy ? null : () => _revoke(s.origin),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  static String _short(String addr) => addr.length > 16
      ? '${addr.substring(0, 8)}…${addr.substring(addr.length - 6)}'
      : addr;
}
