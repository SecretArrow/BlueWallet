import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/wallet_service.dart';
import '../../widgets/tonal_button.dart';
import '../../widgets/octra_card.dart';

/// Receive screen — shows QR code, copy address, and share QR image.
class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final _qrKey = GlobalKey();
  bool _sharing = false;

  void _copy(String address) {
    Clipboard.setData(ClipboardData(text: address));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Address copied to clipboard'),
          duration: Duration(seconds: 2)),
    );
  }

  Future<void> _shareQr(String address) async {
    setState(() => _sharing = true);
    try {
      final boundary =
          _qrKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/octra_qr.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'My Octra address: $address',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WalletService>();
    final address = ws.activeWallet?.address ?? '';
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Receive')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Your Address', style: tt.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  ws.activeWallet?.name ?? '',
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                if (address.isNotEmpty)
                  OctopusCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        RepaintBoundary(
                          key: _qrKey,
                          child: QrImageView(
                            data: address,
                            version: QrVersions.auto,
                            size: 240,
                            backgroundColor: Colors.white,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Colors.black,
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: () => _copy(address),
                          child: Text(
                            address,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const CircularProgressIndicator(),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TonalButton(
                        label: 'Copy Address',
                        icon: Icons.copy_rounded,
                        onPressed:
                            address.isEmpty ? null : () => _copy(address),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TonalButton(
                        label: 'Share QR',
                        icon: Icons.share_rounded,
                        loading: _sharing,
                        onPressed: (address.isEmpty || _sharing)
                            ? null
                            : () => _shareQr(address),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
