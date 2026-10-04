import 'dart:io';
import 'package:flutter/material.dart';
import '../../widgets/octopus_card.dart';

/// Permissions Center — manage app permissions.  Matches PermissionsCenterActivity.
class PermissionsCenterScreen extends StatefulWidget {
  const PermissionsCenterScreen({super.key});

  @override
  State<PermissionsCenterScreen> createState() =>
      _PermissionsCenterScreenState();
}

class _PermissionsCenterScreenState extends State<PermissionsCenterScreen> {
  bool _camera = false;
  bool _biometric = false;
  bool _notifications = false;
  bool _storage = false;

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Permissions Center')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Manage which permissions the app uses.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
          ),
          const SizedBox(height: 16),
          // Camera and biometrics only apply on mobile
          if (_isMobile) ...[
            _PermissionTile(
              icon: Icons.camera_alt_rounded,
              title: 'Camera',
              subtitle: 'Required for QR code scanning',
              value: _camera,
              onChanged: (v) => setState(() => _camera = v),
            ),
            const SizedBox(height: 8),
            _PermissionTile(
              icon: Icons.fingerprint_rounded,
              title: 'Biometrics',
              subtitle: 'Use fingerprint or face to unlock',
              value: _biometric,
              onChanged: (v) => setState(() => _biometric = v),
            ),
            const SizedBox(height: 8),
          ],
          _PermissionTile(
            icon: Icons.notifications_rounded,
            title: 'Notifications',
            subtitle: 'Receive transaction alerts',
            value: _notifications,
            onChanged: (v) => setState(() => _notifications = v),
          ),
          const SizedBox(height: 8),
          _PermissionTile(
            icon: Icons.folder_rounded,
            title: 'Storage',
            subtitle: 'Import/export wallet files',
            value: _storage,
            onChanged: (v) => setState(() => _storage = v),
          ),
        ],
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
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
              color:
                  (value ? cs.primary : cs.onSurfaceVariant).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: value ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
