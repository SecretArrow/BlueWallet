import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/crypto_service.dart';
import '../../services/pin_service.dart';
import '../../services/wallet_service.dart';
import '../../widgets/tonal_button.dart';

/// First-launch screen: create new wallet, import private key, or import file.
/// Matches Android SetupActivity + NewWalletActivity + ImportWalletActivity.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

enum _SetupView { choice, generate, import, pinSetup }

class _SetupScreenState extends State<SetupScreen> {
  _SetupView _view = _SetupView.choice;

  final _nameCtrl = TextEditingController();
  final _pkCtrl = TextEditingController();
  final _pin1Ctrl = TextEditingController();
  final _pin2Ctrl = TextEditingController();

  bool _loading = false;
  String? _error;

  // Imported wallet data — held in memory until PIN is set
  String? _pendingAddress;
  String? _pendingSkBase64;
  String? _pendingName;

  @override
  void initState() {
    super.initState();
    _checkExisting();
  }

  Future<void> _checkExisting() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('wallet_ids') ?? [];
    if (ids.isNotEmpty && mounted) {
      context.go('/pin?mode=unlock');
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pkCtrl.dispose();
    _pin1Ctrl.dispose();
    _pin2Ctrl.dispose();
    super.dispose();
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _doImport() async {
    final pk = _pkCtrl.text.trim();
    if (pk.isEmpty) {
      setState(() => _error = 'Paste your private key');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final kp = await CryptoService.importFromPrivateKey(pk);
      setState(() {
        _pendingAddress = kp['address']!;
        _pendingSkBase64 = kp['sk']!;
        _pendingName = 'My Wallet';
        _view = _SetupView.pinSetup;
      });
    } catch (e) {
      setState(() => _error = 'Invalid private key: $e');
    }
    setState(() => _loading = false);
  }

  Future<void> _doSetPin() async {
    final pin1 = _pin1Ctrl.text.trim();
    final pin2 = _pin2Ctrl.text.trim();
    if (pin1.length != 6) {
      setState(() => _error = 'PIN must be exactly 6 digits');
      return;
    }
    if (pin1 != pin2) {
      setState(() => _error = 'PINs do not match');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await PinService.setPin(pin1);
      if (!mounted) return;
      final ws = context.read<WalletService>();
      await ws.addWalletRaw(
        name: _pendingName!,
        address: _pendingAddress!,
        skBase64: _pendingSkBase64!,
      );
      if (mounted) context.go('/home');
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: switch (_view) {
                _SetupView.choice => _buildChoice(cs, tt),
                _SetupView.generate => _buildChoice(cs, tt),
                _SetupView.import => _buildImport(cs, tt),
                _SetupView.pinSetup => _buildPinSetup(cs, tt),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChoice(ColorScheme cs, TextTheme tt) => Column(
        key: const ValueKey('choice'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Octra Wallet',
            style: tt.displaySmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'No wallet found',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 40),
          if (_error != null) ...[
            _ErrorBanner(_error!),
            const SizedBox(height: 12)
          ],
          // Primary option: Create by Seed Phrase (first)
          SizedBox(
            width: 200,
            child: TonalButton(
              label: 'Create by Seed Phrase',
              icon: Icons.auto_awesome_rounded,
              loading: _loading,
              onPressed:
                  _loading ? null : () => context.push('/mnemonic-wallet'),
            ),
          ),
          const SizedBox(height: 16),
          // Secondary option: Import Private Key
          SizedBox(
            width: 200,
            child: TonalButton(
              label: 'Import Private Key',
              icon: Icons.vpn_key_rounded,
              onPressed: () => setState(() {
                _view = _SetupView.import;
                _error = null;
              }),
            ),
          ),
        ],
      );

  Widget _buildImport(ColorScheme cs, TextTheme tt) => Column(
        key: const ValueKey('import'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Import Wallet', style: tt.headlineMedium),
          const SizedBox(height: 24),
          if (_error != null) ...[
            _ErrorBanner(_error!),
            const SizedBox(height: 12)
          ],
          Text('Private Key (Base64)', style: tt.labelLarge),
          const SizedBox(height: 6),
          TextField(
            controller: _pkCtrl,
            decoration: const InputDecoration(
                hintText: 'Paste your 64-byte key here...'),
            minLines: 3,
            maxLines: 5,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
                child: TonalButton(
                    label: 'Import',
                    loading: _loading,
                    onPressed: _loading ? null : _doImport)),
            const SizedBox(width: 12),
            Expanded(
                child: TonalButton(
                    label: 'Back',
                    onPressed: () => setState(() {
                          _view = _SetupView.choice;
                          _error = null;
                        }))),
          ]),
        ],
      );

  Widget _buildPinSetup(ColorScheme cs, TextTheme tt) => Column(
        key: const ValueKey('pin'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Create PIN', style: tt.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Wallet imported. Set a PIN to protect it.',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          if (_error != null) ...[
            _ErrorBanner(_error!),
            const SizedBox(height: 12)
          ],
          Text('Enter a 6-digit PIN', style: tt.labelLarge),
          const SizedBox(height: 6),
          TextField(
            controller: _pin1Ctrl,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: 6,
            obscureText: true,
            style: const TextStyle(fontSize: 24, letterSpacing: 8),
            decoration:
                const InputDecoration(hintText: '- - - - - -', counterText: ''),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 16),
          Text('Confirm PIN', style: tt.labelLarge),
          const SizedBox(height: 6),
          TextField(
            controller: _pin2Ctrl,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: 6,
            obscureText: true,
            style: const TextStyle(fontSize: 24, letterSpacing: 8),
            decoration:
                const InputDecoration(hintText: '- - - - - -', counterText: ''),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
                child: TonalButton(
                    label: 'Set PIN',
                    loading: _loading,
                    onPressed: _loading ? null : _doSetPin)),
            const SizedBox(width: 12),
            Expanded(
                child: TonalButton(
                    label: 'Back',
                    onPressed: () => setState(() {
                          _view = _SetupView.import;
                          _error = null;
                        }))),
          ]),
        ],
      );
}

// ── Helpers ─────────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner(this.message);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: cs.errorContainer, borderRadius: BorderRadius.circular(10)),
      child: Text(message, style: TextStyle(color: cs.onErrorContainer)),
    );
  }
}
