import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/address_book_service.dart';
import '../../models/address_entry.dart';
import '../../widgets/octra_card.dart';

/// Address book list screen.  Matches AddressBookActivity.
class AddressBookScreen extends StatelessWidget {
  const AddressBookScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final abs = context.watch<AddressBookService>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Address Book')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/address-book-entry'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Address'),
      ),
      body: abs.entries.isEmpty
          ? Center(
              child: Text(
                'No saved addresses',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: abs.entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final e = abs.entries[i];
                return _AddressCard(
                  entry: e,
                  onEdit: () => context.push('/address-book-entry?id=${e.id}'),
                  onDelete: () => abs.remove(e.id),
                  onSend: () => context.push('/send?to=${e.address}'),
                );
              },
            ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  final AddressEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSend;

  const _AddressCard({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
    required this.onSend,
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
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                Icon(Icons.contact_page_rounded, size: 20, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.label,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  entry.address,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'send') onSend();
              if (v == 'edit') onEdit();
              if (v == 'delete') onDelete();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'send', child: Text('Send to')),
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}
