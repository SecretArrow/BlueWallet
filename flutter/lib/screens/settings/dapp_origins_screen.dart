import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/octopus_card.dart';

/// dApp Origins management screen.  Matches DappOriginsActivity.
class DappOriginsScreen extends StatefulWidget {
  const DappOriginsScreen({super.key});

  @override
  State<DappOriginsScreen> createState() => _DappOriginsScreenState();
}

class _DappOriginsScreenState extends State<DappOriginsScreen> {
  List<String> _origins = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _origins = prefs.getStringList('dapp_origins') ?? []);
  }

  Future<void> _add() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add dApp Origin'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Origin URL',
            hintText: 'https://app.example.com',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      final newOrigins = [..._origins, ctrl.text.trim()];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('dapp_origins', newOrigins);
      setState(() => _origins = newOrigins);
    }
  }

  Future<void> _remove(String origin) async {
    _origins.remove(origin);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('dapp_origins', _origins);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('dApp Origins')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Origin'),
      ),
      body: _origins.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.web_rounded,
                      size: 48, color: cs.onSurfaceVariant.withOpacity(0.4)),
                  const SizedBox(height: 12),
                  Text('No allowed dApp origins',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _origins.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => OctopusCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.web_rounded, size: 20, color: cs.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _origins[i],
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline_rounded,
                          size: 18, color: cs.error),
                      onPressed: () => _remove(_origins[i]),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
