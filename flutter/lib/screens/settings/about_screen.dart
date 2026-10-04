import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../widgets/octra_card.dart';
import '../../widgets/adaptive_body.dart';

const _kDonationAddress =
    'oct7f3a8b2c1d9e4f6a0b5c2d7e1f3a8b2c1d9e4f6a0b5c2d7e1f3a8b2c1d9e4f6';

/// About screen — version, donation address.  Matches AboutActivity.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '-';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = info.version);
    } catch (_) {}
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Donation address copied'),
          duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: AdaptiveBody(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Logo
              const SizedBox(height: 12),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: cs.primary.withValues(alpha: 0.3), width: 1.5),
                ),
                child: Icon(Icons.account_balance_wallet_rounded,
                    size: 52, color: cs.primary),
              ),
              const SizedBox(height: 16),
              Text('Octra Wallet', style: tt.headlineMedium),
              const SizedBox(height: 4),
              Text('Version $_version',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 24),
              OctopusCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Maragung',
                        style: tt.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('Built by Octra Community',
                        style:
                            tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    const Divider(height: 24),
                    Text('Donate',
                        style: tt.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    // Always show first 8 + last 8 chars; middle wraps if needed.
                    _DonateAddress(
                      address: _kDonationAddress,
                      onCopy: () => _copy(_kDonationAddress),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              OctopusCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow(label: 'Network', value: 'Octra Mainnet'),
                    _InfoRow(label: 'License', value: 'MIT'),
                    _InfoRow(
                        label: 'Platform', value: 'Flutter (Multi-platform)'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style:
                    const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// Renders a wallet address ensuring the first 8 and last 8 characters are
/// always visible. If the full address fits it is shown as-is; otherwise the
/// text wraps naturally. Never uses TextOverflow.ellipsis.
class _DonateAddress extends StatelessWidget {
  final String address;
  final VoidCallback onCopy;
  const _DonateAddress({required this.address, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            address,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: cs.onSurface,
            ),
            softWrap: true,
          ),
        ),
        IconButton(
          icon: Icon(Icons.copy, size: 18, color: cs.primary),
          onPressed: onCopy,
          tooltip: 'Copy donation address',
        ),
      ],
    );
  }
}
