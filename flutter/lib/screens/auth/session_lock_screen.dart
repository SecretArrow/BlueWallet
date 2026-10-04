import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Session settings screen — matches Android activity_session_lock.xml exactly:
/// "Auto Lock" title with RadioGroup: 5, 10, 15, 25, 30, 60 min, Never.
/// Accessed from Settings → Session.
class SessionLockScreen extends StatefulWidget {
  const SessionLockScreen({super.key});

  @override
  State<SessionLockScreen> createState() => _SessionLockScreenState();
}

class _SessionLockScreenState extends State<SessionLockScreen> {
  static const _prefKey = 'auto_lock_minutes';

  // 0 means Never
  static const _options = [5, 10, 15, 25, 30, 60, 0];

  int _selectedMinutes = 5;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getInt(_prefKey) ?? 5;
    setState(() {
      _selectedMinutes = val;
      _loading = false;
    });
  }

  Future<void> _select(int minutes) async {
    setState(() => _selectedMinutes = minutes);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKey, minutes);
  }

  String _label(int minutes) {
    if (minutes == 0) return 'Never';
    return '$minutes minutes';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                color: cs.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Auto Lock',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Automatically lock the wallet after a period of inactivity.',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      RadioGroup<int>(
                        groupValue: _selectedMinutes,
                        onChanged: (val) {
                          if (val != null) _select(val);
                        },
                        child: Column(
                          children: _options
                              .map((minutes) => RadioListTile<int>(
                                    title: Text(_label(minutes)),
                                    value: minutes,
                                    activeColor: cs.primary,
                                    contentPadding: EdgeInsets.zero,
                                  ))
                              .toList(),
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
