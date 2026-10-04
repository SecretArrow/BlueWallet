import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/address_book_service.dart';
import '../../models/address_entry.dart';
import '../../widgets/tonal_button.dart';

/// Add or edit an address book entry.  Matches AddressBookEntryActivity.
class AddressBookEntryScreen extends StatefulWidget {
  final String? editId;

  const AddressBookEntryScreen({super.key, this.editId});

  @override
  State<AddressBookEntryScreen> createState() => _AddressBookEntryScreenState();
}

class _AddressBookEntryScreenState extends State<AddressBookEntryScreen> {
  final _labelCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.editId != null) {
      final entry = context
          .read<AddressBookService>()
          .entries
          .where((e) => e.id == widget.editId)
          .firstOrNull;
      if (entry != null) {
        _labelCtrl.text = entry.label;
        _addrCtrl.text = entry.address;
      }
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _addrCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final label = _labelCtrl.text.trim();
    final addr = _addrCtrl.text.trim();
    if (label.isEmpty || addr.isEmpty) {
      setState(() => _error = 'Please fill all fields');
      return;
    }
    setState(() => _loading = true);
    final abs = context.read<AddressBookService>();
    if (widget.editId != null) {
      await abs.update(AddressEntry(
          id: widget.editId!, label: label, address: addr));
    } else {
      await abs.add(AddressEntry(
        id: 'addr_${DateTime.now().millisecondsSinceEpoch}',
        label: label,
        address: addr,
      ));
    }
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isEdit = widget.editId != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit Address' : 'Add Address')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_error!, style: TextStyle(color: cs.onErrorContainer)),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _labelCtrl,
              decoration: const InputDecoration(
                labelText: 'Label',
                hintText: 'e.g. Alice, Exchange...',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _addrCtrl,
              decoration: InputDecoration(
                labelText: 'Address',
                hintText: 'oct...',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  onPressed: () async {
                    final result = await context.push<String>('/qr-scan');
                    if (result != null && mounted) {
                      _addrCtrl.text = result;
                    }
                  },
                ),
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
            const SizedBox(height: 24),
            TonalButton(
              label: isEdit ? 'Update' : 'Save',
              loading: _loading,
              onPressed: _loading ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
