import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/tor_proxy_service.dart';
import '../../widgets/octopus_card.dart';

class TorProxySettingsScreen extends StatefulWidget {
  const TorProxySettingsScreen({super.key});

  @override
  State<TorProxySettingsScreen> createState() => _TorProxySettingsScreenState();
}

class _TorProxySettingsScreenState extends State<TorProxySettingsScreen> {
  void _showAddServerDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final hostCtrl = TextEditingController();
    final portCtrl = TextEditingController();
    String type = 'SOCKS';
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final cs = Theme.of(context).colorScheme;
          return AlertDialog(
            title: const Text('Add Custom Proxy'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Proxy Name',
                        hintText: 'e.g. My Tor Node',
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Name is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: hostCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Host IP or Domain',
                        hintText: 'e.g. 127.0.0.1 or myproxy.com',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Host is required';
                        final trim = v.trim();
                        if (trim.contains(' ')) return 'Invalid hostname';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: portCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        hintText: 'e.g. 9050',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Port is required';
                        final p = int.tryParse(v.trim());
                        if (p == null || p < 1 || p > 65535) {
                          return 'Port must be between 1 and 65535';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Proxy Type:'),
                        Row(
                          children: [
                            ChoiceChip(
                              label: const Text('SOCKS5'),
                              selected: type == 'SOCKS',
                              onSelected: (selected) {
                                if (selected) setModalState(() => type = 'SOCKS');
                              },
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('HTTP'),
                              selected: type == 'HTTP',
                              onSelected: (selected) {
                                if (selected) setModalState(() => type = 'HTTP');
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState?.validate() ?? false) {
                    final tor = context.read<TorProxyService>();
                    tor.addProxyServer(ProxyConfig(
                      name: nameCtrl.text.trim(),
                      host: hostCtrl.text.trim(),
                      port: int.parse(portCtrl.text.trim()),
                      type: type,
                    ));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Proxy server added successfully')),
                    );
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, ProxyConfig server) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Proxy'),
        content: Text('Are you sure you want to remove "${server.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<TorProxyService>().removeProxyServer(server.host, server.port);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Proxy server removed')),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tor = context.watch<TorProxyService>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tor Proxy Settings'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddServerDialog(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Proxy'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card
            OctopusCard(
              padding: const EdgeInsets.all(16.0),
              radius: 20,
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: tor.enabled
                          ? cs.primary.withOpacity(0.12)
                          : cs.onSurface.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.shield_rounded,
                      color: tor.enabled ? cs.primary : cs.onSurfaceVariant,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Route RPC via Tor',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tor.enabled
                              ? 'Enabled (${tor.activeType} at ${tor.activeHost}:${tor.activePort})'
                              : 'Disabled (Direct connection)',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: tor.enabled,
                    onChanged: (val) {
                      tor.setEnabled(val);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(val
                              ? 'Tor routing enabled'
                              : 'Tor routing disabled - Direct connections active'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Server list title
            Padding(
              padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
              child: Text(
                'Available Proxies',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: cs.primary,
                  letterSpacing: 0.5,
                ),
              ),
            ),

            // Server List Card
            OctopusCard(
              padding: EdgeInsets.zero,
              radius: 20,
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: tor.servers.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: cs.onSurface.withOpacity(0.08),
                ),
                itemBuilder: (context, i) {
                  final s = tor.servers[i];
                  final isActive = tor.activeHost == s.host && tor.activePort == s.port && tor.activeType == s.type;

                  return InkWell(
                    onTap: () {
                      tor.setActiveProxy(s.host, s.port, s.type);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Switched proxy to ${s.name}'),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.only(
                      topLeft: i == 0 ? const Radius.circular(20) : Radius.zero,
                      topRight: i == 0 ? const Radius.circular(20) : Radius.zero,
                      bottomLeft: i == tor.servers.length - 1 ? const Radius.circular(20) : Radius.zero,
                      bottomRight: i == tor.servers.length - 1 ? const Radius.circular(20) : Radius.zero,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                      child: Row(
                        children: [
                          // Active status indicator
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? (tor.enabled ? Colors.green : cs.primary.withOpacity(0.4))
                                  : Colors.transparent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isActive
                                    ? (tor.enabled ? Colors.green : cs.primary)
                                    : cs.onSurfaceVariant.withOpacity(0.4),
                                width: 2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      s.name,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (s.isDefault)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: cs.primary.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'Default',
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: cs.primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    if (isActive)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 4.0),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: tor.enabled
                                                ? Colors.green.withOpacity(0.1)
                                                : cs.primary.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            tor.enabled ? 'ACTIVE' : 'SELECTED',
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: tor.enabled ? Colors.green : cs.primary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${s.type} • ${s.host}:${s.port}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!s.isDefault)
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded),
                              color: cs.error,
                              iconSize: 20,
                              onPressed: () => _confirmDelete(context, s),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            // Explanatory footer
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tor routes your RPC requests through onion circuits to mask your IP address. For local proxy setups, install Orbot and enable its SOCKS (port 9050) or HTTP (port 8118) server. Dynamic OkHttp-equivalent proxying is applied to all active network calls automatically.',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 80), // extra padding for fab
          ],
        ),
      ),
    );
  }
}
