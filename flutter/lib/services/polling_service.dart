import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PollingService extends ChangeNotifier {
  static const String _kIntervalKey = 'polling_interval_ms';
  static const String _kThresholdSendKey = 'threshold_send_ms';
  static const String _kThresholdAdvancedKey = 'threshold_advanced_ms';

  static const int defaultIntervalMs = 5000;
  static const int defaultThresholdSendMs = 300000; // 5m
  static const int defaultThresholdAdvancedMs = 600000; // 10m

  int _intervalMs = defaultIntervalMs;
  int _thresholdSendMs = defaultThresholdSendMs;
  int _thresholdAdvancedMs = defaultThresholdAdvancedMs;

  int get intervalMs => _intervalMs;
  int get thresholdSendMs => _thresholdSendMs;
  int get thresholdAdvancedMs => _thresholdAdvancedMs;

  PollingService() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _intervalMs = prefs.getInt(_kIntervalKey) ?? defaultIntervalMs;
    _thresholdSendMs = prefs.getInt(_kThresholdSendKey) ?? defaultThresholdSendMs;
    _thresholdAdvancedMs = prefs.getInt(_kThresholdAdvancedKey) ?? defaultThresholdAdvancedMs;
    notifyListeners();
  }

  Future<void> setSettings({
    required int intervalMs,
    required int thresholdSendMs,
    required int thresholdAdvancedMs,
  }) async {
    _intervalMs = intervalMs;
    _thresholdSendMs = thresholdSendMs;
    _thresholdAdvancedMs = thresholdAdvancedMs;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kIntervalKey, intervalMs);
    await prefs.setInt(_kThresholdSendKey, thresholdSendMs);
    await prefs.setInt(_kThresholdAdvancedKey, thresholdAdvancedMs);
    
    notifyListeners();
  }
}
