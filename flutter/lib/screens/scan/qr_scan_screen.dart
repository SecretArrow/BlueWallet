import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// QR Scan screen — camera scanner that returns an address string.
/// Used by SendScreen, AddressBookEntryScreen, etc.
///
/// On mobile: camera-based QR scanning (stub/demo for now).
/// On desktop: provides "Paste from Clipboard" as the primary input method.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _simulating = false;
  final _pasteCtrl = TextEditingController();

  @override
  void dispose() {
    _pasteCtrl.dispose();
    super.dispose();
  }

  bool get _isDesktop =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  Future<void> _simulate() async {
    setState(() => _simulating = true);
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      context.pop('oct1qABCDExampleAddress');
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty && mounted) {
      context.pop(text);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clipboard is empty')),
      );
    }
  }

  void _submitManual() {
    final text = _pasteCtrl.text.trim();
    if (text.isNotEmpty && mounted) {
      context.pop(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: _isDesktop ? null : Colors.black,
      appBar: AppBar(
        backgroundColor: _isDesktop ? null : Colors.black,
        foregroundColor: _isDesktop ? null : Colors.white,
        title: Text(_isDesktop ? 'Enter Address' : 'Scan QR Code'),
      ),
      body: _isDesktop ? _buildDesktopBody(cs) : _buildMobileBody(cs),
    );
  }

  Widget _buildDesktopBody(ColorScheme cs) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.content_paste_rounded, size: 48, color: cs.primary),
              const SizedBox(height: 16),
              Text(
                'Paste or type the recipient address',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _pasteCtrl,
                decoration: InputDecoration(
                  labelText: 'Address',
                  hintText: 'oct...',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.content_paste_rounded),
                    onPressed: () async {
                      final data =
                          await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text != null) {
                        _pasteCtrl.text = data!.text!.trim();
                      }
                    },
                    tooltip: 'Paste',
                  ),
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                onSubmitted: (_) => _submitManual(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _submitManual,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Use Address'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pasteFromClipboard,
                      icon: const Icon(Icons.content_paste_go_rounded),
                      label: const Text('Paste & Go'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileBody(ColorScheme cs) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: cs.primary, width: 2.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.qr_code_scanner_rounded,
                    size: 80, color: cs.primary.withValues(alpha: 0.4)),
              ),
              const SizedBox(height: 24),
              const Text(
                'Point camera at a QR code',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 20),
              if (!_simulating) ...[
                OutlinedButton.icon(
                  onPressed: _simulate,
                  icon: const Icon(Icons.qr_code_rounded, color: Colors.white),
                  label: const Text('Simulate Scan (Demo)',
                      style: TextStyle(color: Colors.white)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white54),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste_rounded,
                      color: Colors.white),
                  label: const Text('Paste from Clipboard',
                      style: TextStyle(color: Colors.white)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white54),
                  ),
                ),
              ] else
                const CircularProgressIndicator(color: Colors.white),
            ],
          ),
        ),
      ],
    );
  }
}
