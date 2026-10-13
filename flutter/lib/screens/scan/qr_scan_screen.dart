import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// QR Scan screen — real camera scanning that returns an address string.
/// Used by SendScreen, AddressBookEntryScreen, etc.
///
/// - Mobile: full-bleed camera preview ([MobileScanner]) with a scan-frame
///   overlay, torch toggle, and clipboard / manual entry fallbacks. The
///   CAMERA permission is requested at runtime by mobile_scanner when the
///   preview starts; a denied permission, a missing camera, or an
///   unsupported platform falls back to the manual entry card — never a
///   dead end, never a simulated result.
/// - Desktop: paste / type the address directly (no camera assumed).
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _pasteCtrl = TextEditingController();

  /// Pop-once guard: detection bursts must not pop the route twice.
  bool _popped = false;

  /// Camera unavailable / permission denied / unsupported platform → show
  /// the manual entry card (the same one the desktop branch uses).
  bool _cameraFailed = false;

  /// Manual entry explicitly requested via the bottom controls.
  bool _manualRequested = false;

  bool _torchOn = false;

  /// Created lazily (mobile branch only) so the desktop branch and widget
  /// tests never touch the camera plugin.
  MobileScannerController? _scanner;

  @override
  void dispose() {
    _scanner?.dispose();
    _pasteCtrl.dispose();
    super.dispose();
  }

  /// Desktop = Linux / Windows / macOS. Uses [defaultTargetPlatform] (not
  /// `dart:io` Platform) so widget tests can select either branch with
  /// `debugDefaultTargetPlatformOverride`.
  bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS;

  void _popWith(String value) {
    if (_popped || !mounted) return;
    _popped = true;
    context.pop(value);
  }

  void _onDetect(BarcodeCapture capture) {
    if (_popped) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.trim().isEmpty) continue;
      _popWith(value.trim());
      return;
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty && mounted) {
      _popWith(text);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clipboard is empty')),
      );
    }
  }

  void _submitManual() {
    final text = _pasteCtrl.text.trim();
    if (text.isNotEmpty && mounted) {
      _popWith(text);
    }
  }

  Future<void> _toggleTorch() async {
    final scanner = _scanner;
    if (scanner == null) return;
    try {
      // Toggling talks to camera hardware asynchronously; a rejected Future
      // (missing torch on emulators / front cameras) must not go unhandled.
      await scanner.toggleTorch();
    } catch (e) {
      // Torch hardware missing — the scanner stays usable, just without the
      // light.
      debugPrint('QR torch toggle failed: $e');
      return;
    }
    if (mounted) setState(() => _torchOn = !_torchOn);
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

  Widget _buildDesktopBody(ColorScheme cs) => _buildManualEntryCard(cs);

  Widget _buildMobileBody(ColorScheme cs) {
    if (_cameraFailed || _manualRequested) {
      return _buildManualEntryCard(cs);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildCameraPreview(),
        _buildScanOverlay(cs),
      ],
    );
  }

  Widget _buildCameraPreview() {
    // Try-builder: mobile_scanner may throw on platforms without camera
    // support — fall back to the manual card instead of crashing.
    try {
      return MobileScanner(
        controller: _scanner ??= MobileScannerController(
          // Payment QRs only: ignore 1D / other barcode noise.
          formats: const [BarcodeFormat.qrCode],
        ),
        onDetect: _onDetect,
        errorBuilder: (context, error) {
          // Permission denied, camera busy, or preview failure: flip to the
          // manual entry card (post-frame — no setState during build).
          if (!_cameraFailed) {
            debugPrint('QR scanner camera error: $error');
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _cameraFailed = true);
            });
          }
          return const SizedBox.shrink();
        },
      );
    } catch (e) {
      debugPrint('QR scanner unavailable on this platform: $e');
      return _buildManualEntryCard(Theme.of(context).colorScheme);
    }
  }

  Widget _buildScanOverlay(ColorScheme cs) {
    return SafeArea(
      child: Column(
        children: [
          const Spacer(),
          Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: cs.primary, width: 2.5),
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Point camera at a QR code',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const Spacer(),
          _buildControlsRow(),
        ],
      ),
    );
  }

  Widget _buildControlsRow() {
    return Container(
      color: Colors.black54,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            tooltip: _torchOn ? 'Turn torch off' : 'Turn torch on',
            color: Colors.white,
            icon: Icon(_torchOn ? Icons.flashlight_on : Icons.flashlight_off),
            onPressed: _toggleTorch,
          ),
          IconButton(
            tooltip: 'Paste from clipboard',
            color: Colors.white,
            icon: const Icon(Icons.content_paste_rounded),
            onPressed: _pasteFromClipboard,
          ),
          IconButton(
            tooltip: 'Enter address manually',
            color: Colors.white,
            icon: const Icon(Icons.keyboard_alt_rounded),
            onPressed: () => setState(() => _manualRequested = true),
          ),
        ],
      ),
    );
  }

  /// Manual / desktop entry card: paste or type the address.
  Widget _buildManualEntryCard(ColorScheme cs) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
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
                        if (data?.text != null && context.mounted) {
                          final pasted = data?.text?.trim() ?? '';
                          if (pasted.isNotEmpty) _pasteCtrl.text = pasted;
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
      ),
    );
  }
}
