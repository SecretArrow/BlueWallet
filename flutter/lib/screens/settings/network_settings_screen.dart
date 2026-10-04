import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/network_service.dart';
import '../../models/network_profile.dart';
import '../../widgets/octopus_card.dart';

/// Network settings — list, add, edit, remove, set active node.
/// Matches Android NetworkSettingsActivity + AddNetworkActivity exactly:
///   • Three fields: Network Name, RPC URL, Explorer URL
///   • RPC allows http:// or https://; warns on cleartext HTTP (non-trusted)
///   • Explorer requires https://; empty → NetworkService.defaultExplorer
///   • Edit mode disables the Name field (mirrors Android nameInput.setEnabled(false))
class NetworkSettingsScreen extends StatelessWidget {
  const NetworkSettingsScreen({super.key});

  // ── Trusted cleartext hosts (mirrors Android UrlSecurityValidator) ────────
  static bool _isTrustedCleartext(String rpcUrl) {
    final uri = Uri.tryParse(rpcUrl.trim());
    if (uri == null) return true;
    if (uri.scheme != 'http') return true; // https is always fine
    final host = uri.host.toLowerCase();
    return host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '165.227.225.79';
  }

  // ── URL normalisation (mirrors Android UrlSecurityValidator) ─────────────

  static String? _normaliseRpc(String input) {
    String s = input.trim();
    if (s.isEmpty) return null;
    if (!s.contains('://')) s = 'http://$s';
    final uri = Uri.tryParse(s);
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    return s;
  }

  /// Explorer requires https.  Empty string → defaultExplorer.
  static String? _normaliseExplorer(String input) {
    String s = input.trim();
    if (s.isEmpty) return NetworkService.defaultExplorer;
    if (!s.contains('://')) s = 'https://$s';
    final uri = Uri.tryParse(s);
    if (uri == null) return null;
    if (uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    return s;
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────

  Future<void> _showAddDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final rpcCtrl = TextEditingController();
    final explorerCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final ns = context.read<NetworkService>();

    bool nameExists(String name) =>
        ns.profiles.any((p) => p.name.toLowerCase() == name.toLowerCase());

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _NetworkFormDialog(
        title: 'Add Network',
        nameCtrl: nameCtrl,
        rpcCtrl: rpcCtrl,
        explorerCtrl: explorerCtrl,
        formKey: formKey,
        nameReadOnly: false,
        nameExistsCheck: nameExists,
        normaliseRpc: _normaliseRpc,
        normaliseExplorer: _normaliseExplorer,
        isTrustedCleartext: _isTrustedCleartext,
        onSave: (name, rpc, explorer) {
          ns.addProfile(NetworkProfile(
            id: 'node_${DateTime.now().millisecondsSinceEpoch}',
            name: name,
            nodeUrl: rpc,
            explorerUrl: explorer,
          ));
        },
      ),
    );
  }

  Future<void> _showEditDialog(
      BuildContext context, NetworkProfile profile) async {
    final nameCtrl = TextEditingController(text: profile.name);
    final rpcCtrl = TextEditingController(text: profile.nodeUrl);
    final explorerCtrl = TextEditingController(text: profile.explorerUrl);
    final formKey = GlobalKey<FormState>();
    final ns = context.read<NetworkService>();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _NetworkFormDialog(
        title: 'Edit Network',
        nameCtrl: nameCtrl,
        rpcCtrl: rpcCtrl,
        explorerCtrl: explorerCtrl,
        formKey: formKey,
        nameReadOnly: true, // matches Android nameInput.setEnabled(false)
        nameExistsCheck: (_) => false,
        normaliseRpc: _normaliseRpc,
        normaliseExplorer: _normaliseExplorer,
        isTrustedCleartext: _isTrustedCleartext,
        onSave: (name, rpc, explorer) {
          ns.updateProfile(profile.id, nodeUrl: rpc, explorerUrl: explorer);
        },
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, NetworkService ns, NetworkProfile p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Network'),
        content: Text('Remove "${p.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ns.removeProfile(p.id);
            },
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ns = context.watch<NetworkService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Network Settings')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Network'),
      ),
      body: OctopusCard(
        padding: EdgeInsets.zero,
        radius: 20,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Networks',
                    style: Theme.of(context).textTheme.headlineSmall),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(8),
                itemCount: ns.profiles.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final p = ns.profiles[i];
                  return _NetworkTile(
                    profile: p,
                    onSetActive: () => ns.setActive(p.id),
                    onEdit: () => _showEditDialog(context, p),
                    onDelete: ns.profiles.length > 1
                        ? () => _confirmDelete(context, ns, p)
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Form dialog (stateful for inline cleartext warning) ───────────────────────

class _NetworkFormDialog extends StatefulWidget {
  final String title;
  final TextEditingController nameCtrl;
  final TextEditingController rpcCtrl;
  final TextEditingController explorerCtrl;
  final GlobalKey<FormState> formKey;
  final bool nameReadOnly;
  final bool Function(String) nameExistsCheck;
  final String? Function(String) normaliseRpc;
  final String? Function(String) normaliseExplorer;
  final bool Function(String) isTrustedCleartext;
  final void Function(String name, String rpc, String explorer) onSave;

  const _NetworkFormDialog({
    required this.title,
    required this.nameCtrl,
    required this.rpcCtrl,
    required this.explorerCtrl,
    required this.formKey,
    required this.nameReadOnly,
    required this.nameExistsCheck,
    required this.normaliseRpc,
    required this.normaliseExplorer,
    required this.isTrustedCleartext,
    required this.onSave,
  });

  @override
  State<_NetworkFormDialog> createState() => _NetworkFormDialogState();
}

class _NetworkFormDialogState extends State<_NetworkFormDialog> {
  bool _showCleartextHint = false;
  String? _pendingName;
  String? _pendingRpc;
  String? _pendingExplorer;

  void _onRpcChanged(String value) {
    final normalised = widget.normaliseRpc(value);
    setState(() {
      _showCleartextHint =
          normalised != null && !widget.isTrustedCleartext(normalised);
    });
  }

  void _trySave() {
    if (!widget.formKey.currentState!.validate()) return;

    final name = widget.nameCtrl.text.trim();
    final rpc = widget.normaliseRpc(widget.rpcCtrl.text.trim());
    if (rpc == null) return;
    final explorer = widget.normaliseExplorer(widget.explorerCtrl.text.trim());
    if (explorer == null) return;

    // Cleartext HTTP on non-trusted host → confirm (matches Android)
    if (!widget.isTrustedCleartext(rpc)) {
      _pendingName = name;
      _pendingRpc = rpc;
      _pendingExplorer = explorer;
      _showCleartextConfirm();
      return;
    }

    widget.onSave(name, rpc, explorer);
    Navigator.pop(context);
  }

  Future<void> _showCleartextConfirm() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unencrypted RPC Connection'),
        content: const Text(
          'This RPC endpoint uses HTTP. Network traffic may be visible '
          'to others. Continue only if you trust this network.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      widget.onSave(_pendingName!, _pendingRpc!, _pendingExplorer!);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Form(
          key: widget.formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Network Name ─────────────────────────────────────────────
              TextFormField(
                controller: widget.nameCtrl,
                readOnly: widget.nameReadOnly,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Network Name',
                  hintText: widget.nameReadOnly ? null : 'e.g. Octra Devnet',
                  filled: widget.nameReadOnly,
                  fillColor:
                      widget.nameReadOnly ? cs.surfaceContainerHighest : null,
                ),
                validator: (v) {
                  if (widget.nameReadOnly) return null;
                  if (v == null || v.trim().isEmpty) {
                    return 'Network name is required';
                  }
                  if (widget.nameExistsCheck(v.trim())) {
                    return 'A network with this name already exists';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // ── RPC URL ──────────────────────────────────────────────────
              TextFormField(
                controller: widget.rpcCtrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                onChanged: _onRpcChanged,
                decoration: const InputDecoration(
                  labelText: 'RPC URL',
                  hintText: 'http://165.227.225.79:8080',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'RPC URL is required';
                  }
                  final n = widget.normaliseRpc(v);
                  if (n == null) {
                    return 'Invalid URL. Use http:// or https:// with a valid host.';
                  }
                  return null;
                },
              ),

              // Inline cleartext hint
              if (_showCleartextHint) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 13, color: cs.error),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'HTTP — you will be asked to confirm.',
                        style: TextStyle(fontSize: 11, color: cs.error),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),

              // ── Explorer URL ─────────────────────────────────────────────
              TextFormField(
                controller: widget.explorerCtrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _trySave(),
                decoration: InputDecoration(
                  labelText: 'Explorer URL',
                  hintText: NetworkService.defaultExplorer,
                  helperText: 'Leave empty to use default (https required)',
                  helperMaxLines: 2,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final n = widget.normaliseExplorer(v);
                  if (n == null) {
                    return 'Explorer URL must use https://';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _trySave,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ── Network list tile ─────────────────────────────────────────────────────────

class _NetworkTile extends StatelessWidget {
  final NetworkProfile profile;
  final VoidCallback onSetActive;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  const _NetworkTile({
    required this.profile,
    required this.onSetActive,
    required this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: profile.isActive
              ? cs.primary.withValues(alpha: 0.15)
              : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.lan_rounded,
          color: profile.isActive ? cs.primary : cs.onSurfaceVariant,
          size: 18,
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              profile.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (profile.isActive) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SubRow(label: 'RPC', value: profile.nodeUrl),
            _SubRow(
              label: 'Explorer',
              value: profile.explorerUrl.isEmpty ? '—' : profile.explorerUrl,
              dim: profile.explorerUrl.isEmpty,
            ),
          ],
        ),
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.edit_outlined, color: cs.primary, size: 20),
            onPressed: onEdit,
            tooltip: 'Edit',
            visualDensity: VisualDensity.compact,
          ),
          if (!profile.isActive)
            TextButton(
              onPressed: onSetActive,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: const Text('Activate'),
            ),
          if (onDelete != null)
            IconButton(
              icon:
                  Icon(Icons.delete_outline_rounded, color: cs.error, size: 20),
              onPressed: onDelete,
              tooltip: 'Delete',
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

class _SubRow extends StatelessWidget {
  final String label;
  final String value;
  final bool dim;

  const _SubRow({required this.label, required this.value, this.dim = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          '$label: ',
          style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: dim ? cs.onSurfaceVariant : null,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
