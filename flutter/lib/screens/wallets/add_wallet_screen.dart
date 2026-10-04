import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/crypto_service.dart';
import '../../services/wallet_service.dart';
import '../../widgets/tonal_button.dart';

/// Add / import wallet screen. Matches Android AddWalletActivity.
class AddWalletScreen extends StatefulWidget {
  const AddWalletScreen({super.key});

  @override
  State<AddWalletScreen> createState() => _AddWalletScreenState();
}

enum _AddMode { none, importKey, importFile }

class _AddWalletScreenState extends State<AddWalletScreen> {
  _AddMode _mode = _AddMode.none;

  final _nameCtrl = TextEditingController();
  final _pkCtrl = TextEditingController();

  bool _loading = false;
  String? _error;
  String? _status;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pkCtrl.dispose();
    super.dispose();
  }

  Future<void> _doGenerate() async {
    setState(() { _loading = true; _error = null; _status = 'Generating keypair...'; });
    try {
      final kp = await CryptoService.generateKeyPair();
      final ws = context.read<WalletService>();
      final name = 'Wallet ${ws.wallets.length + 1}';
      await ws.addWalletRaw(
        name: name,
        address: kp['address']!,
        skBase64: kp['sk']!,
      );
      if (mounted) {
        setState(() { _loading = false; _status = 'Wallet "$name" created!'; });
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) context.pop();
      }
    } catch (e) {
      setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  Future<void> _doImportKey() async {
    final name = _nameCtrl.text.trim();
    final pk = _pkCtrl.text.trim();
    if (name.isEmpty) { setState(() => _error = 'Enter a wallet name'); return; }
    if (pk.isEmpty) { setState(() => _error = 'Paste your private key'); return; }
    setState(() { _loading = true; _error = null; _status = 'Importing...'; });
    try {
      final ws = context.read<WalletService>();
      await ws.importWallet(name: name, privateKey: pk);
      if (mounted) {
        setState(() { _loading = false; _status = 'Wallet imported!'; });
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) context.pop();
      }
    } catch (e) {
      setState(() { _loading = false; _error = 'Invalid key: ${e.toString().replaceFirst('Exception: ', '')}'; });
    }
  }

  Future<void> _doImportFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'key', 'txt'],
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.first.path;
      if (path == null) return;
      final content = await File(path).readAsString();
      // Try to parse as JSON backup
      try {
        final json = jsonDecode(content.trim()) as Map<String, dynamic>;
        final pk = json['private_key']?.toString() ?? json['sk']?.toString() ?? '';
        final name = json['name']?.toString() ?? 'Imported Wallet';
        _nameCtrl.text = name;
        _pkCtrl.text = pk;
      } catch (_) {
        // Plain text key
        _pkCtrl.text = content.trim();
      }
      setState(() { _mode = _AddMode.importKey; _error = null; });
    } catch (e) {
      setState(() => _error = 'Failed to read file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Add Account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: switch (_mode) {
            _AddMode.none => [_buildChoice(cs, tt)],
            _AddMode.importKey => [_buildImportKey(cs, tt)],
            _AddMode.importFile => [_buildImportKey(cs, tt)],
          },
        ),
      ),
    );
  }

  Widget _buildChoice(ColorScheme cs, TextTheme tt) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Add Account', style: tt.headlineMedium),
      const SizedBox(height: 8),
      Text('Choose how to add a wallet account.',
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
      const SizedBox(height: 32),

      // ── Primary: Seed Phrase ─────────────────────────────────────────────
      Card(
        color: cs.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Create with Seed Phrase',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                'Generate a 12-word recovery phrase for your wallet. '
                'You can restore your wallet on any device using this phrase.',
                style: tt.bodySmall?.copyWith(color: cs.onPrimaryContainer),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('Create Seed Phrase Wallet'),
                  onPressed: () => context.push('/mnemonic-wallet'),
                ),
              ),
            ],
          ),
        ),
      ),

      const SizedBox(height: 20),
      const Divider(),
      const SizedBox(height: 8),
      Text('Other options', style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
      const SizedBox(height: 12),

      TonalButton(
        label: 'Generate Random Wallet',
        icon: Icons.shuffle_rounded,
        loading: _loading,
        onPressed: _loading ? null : _doGenerate,
      ),
      const SizedBox(height: 12),
      TonalButton(
        label: 'Import via Private Key',
        icon: Icons.vpn_key_rounded,
        onPressed: () => setState(() { _mode = _AddMode.importKey; _error = null; }),
      ),
      const SizedBox(height: 12),
      TonalButton(
        label: 'Import from File',
        icon: Icons.file_open_rounded,
        onPressed: _doImportFile,
      ),
      const SizedBox(height: 24),
      if (_status != null) Text(_status!, style: TextStyle(color: cs.primary)),
      if (_error != null) Text(_error!, style: TextStyle(color: cs.error)),
    ],
  );

  Widget _buildImportKey(ColorScheme cs, TextTheme tt) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Import Wallet', style: tt.headlineMedium),
      const SizedBox(height: 24),
      if (_error != null) ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.errorContainer, borderRadius: BorderRadius.circular(10)),
          child: Text(_error!, style: TextStyle(color: cs.onErrorContainer)),
        ),
        const SizedBox(height: 12),
      ],
      TextField(
        controller: _nameCtrl,
        decoration: const InputDecoration(labelText: 'Wallet Name', hintText: 'e.g. My Main Wallet'),
        textCapitalization: TextCapitalization.words,
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _pkCtrl,
        decoration: const InputDecoration(
          labelText: 'Private Key (Base64 or Hex)',
          hintText: 'Paste private key...',
        ),
        minLines: 3,
        maxLines: 5,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
      const SizedBox(height: 24),
      Row(children: [
        Expanded(child: TonalButton(label: 'Import', loading: _loading,
            onPressed: _loading ? null : _doImportKey)),
        const SizedBox(width: 12),
        Expanded(child: TonalButton(label: 'Back',
            onPressed: () => setState(() { _mode = _AddMode.none; _error = null; }))),
      ]),
    ],
  );
}
