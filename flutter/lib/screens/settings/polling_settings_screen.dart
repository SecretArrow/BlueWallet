import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../services/polling_service.dart';
import '../../widgets/octopus_card.dart';

class PollingSettingsScreen extends StatefulWidget {
  const PollingSettingsScreen({super.key});

  @override
  State<PollingSettingsScreen> createState() => _PollingSettingsScreenState();
}

class _PollingSettingsScreenState extends State<PollingSettingsScreen> {
  /// Convenience quick-select presets for the interval field (seconds ->
  /// label). Tapping a chip just fills the text field; validation and the
  /// save flow are unchanged.
  static const Map<int, String> _intervalPresets = {
    30: '30s',
    60: '1 min',
    300: '5 min',
    900: '15 min',
  };

  final _intervalController = TextEditingController();
  final _sendThresholdController = TextEditingController();
  final _advancedThresholdController = TextEditingController();

  /// True once the user (or a quick-chip) edits any field — guards the
  /// post-`ready` re-sync below from clobbering live input.
  bool _fieldsEdited = false;

  @override
  void initState() {
    super.initState();
    final ps = context.read<PollingService>();
    // First sync may read defaults: PollingService._load() is async, so the
    // persisted values can land after this screen mounted. Re-sync once the
    // load completes — but never over fields the user already touched.
    _syncFromService(ps);
    for (final controller in [
      _intervalController,
      _sendThresholdController,
      _advancedThresholdController,
    ]) {
      controller.addListener(() => _fieldsEdited = true);
    }
    ps.ready.then((_) {
      if (mounted && !_fieldsEdited) _syncFromService(ps);
    });
  }

  void _syncFromService(PollingService ps) {
    _intervalController.text = (ps.intervalMs ~/ 1000).toString();
    _sendThresholdController.text = (ps.thresholdSendMs ~/ 60000).toString();
    _advancedThresholdController.text =
        (ps.thresholdAdvancedMs ~/ 60000).toString();
    // Our own programmatic writes fired the listeners above; they must not
    // count as user edits.
    _fieldsEdited = false;
  }

  @override
  void dispose() {
    _intervalController.dispose();
    _sendThresholdController.dispose();
    _advancedThresholdController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ps = context.read<PollingService>();
    // Block on the persisted-state load: saving the (possibly stale)
    // defaults while `_load()` is still in flight would overwrite the
    // user's previously persisted settings.
    await ps.ready;
    if (!mounted) return;
    final intInterval = int.tryParse(_intervalController.text);
    final intSend = int.tryParse(_sendThresholdController.text);
    final intAdvanced = int.tryParse(_advancedThresholdController.text);

    if (intInterval == null ||
        intSend == null ||
        intAdvanced == null ||
        intInterval < 1 ||
        intSend < 1 ||
        intAdvanced < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid positive numbers')),
      );
      return;
    }
    // Mirror PollingService bounds (service throws beyond these).
    if (intInterval > 86400 || intSend > 10080 || intAdvanced > 10080) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Interval max 86400s (24h), thresholds max 10080m (7d)')),
      );
      return;
    }

    await ps.setSettings(
      intervalMs: intInterval * 1000,
      thresholdSendMs: intSend * 60000,
      thresholdAdvancedMs: intAdvanced * 60000,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Polling settings saved')),
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Polling Settings')),
      body: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: OctopusCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Polling Interval (seconds)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _intervalController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: '5',
                    helperText:
                        'Seconds between each status check (Default: 5s)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in _intervalPresets.entries)
                      ActionChip(
                        label: Text(entry.value),
                        onPressed: () =>
                            _intervalController.text = '${entry.key}',
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 24),
                const Text(
                  'Send Timeout Threshold (minutes)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _sendThresholdController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: '5',
                    helperText: 'Minutes before prompting etc. (Default: 5m)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 24),
                const Text(
                  'Advanced Timeout (minutes)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Text(
                  'Includes Stealth Send, Encrypt, and Decrypt Balance',
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _advancedThresholdController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: '10',
                    helperText: 'Default: 10m',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: _save,
                    child: const Text('Save Settings'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
