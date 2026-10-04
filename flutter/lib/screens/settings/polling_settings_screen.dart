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
  final _intervalController = TextEditingController();
  final _sendThresholdController = TextEditingController();
  final _advancedThresholdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final ps = context.read<PollingService>();
    _intervalController.text = (ps.intervalMs ~/ 1000).toString();
    _sendThresholdController.text = (ps.thresholdSendMs ~/ 60000).toString();
    _advancedThresholdController.text =
        (ps.thresholdAdvancedMs ~/ 60000).toString();
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
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
                  helperText: 'Seconds between each status check (Default: 5s)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
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
    );
  }
}
