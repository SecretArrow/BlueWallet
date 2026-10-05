import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PollingService extends ChangeNotifier {
  static const String _kIntervalKey = 'polling_interval_ms';
  static const String _kThresholdSendKey = 'threshold_send_ms';
  static const String _kThresholdAdvancedKey = 'threshold_advanced_ms';

  static const int defaultIntervalMs = 5000;
  static const int defaultThresholdSendMs = 300000; // 5m
  static const int defaultThresholdAdvancedMs = 600000; // 10m

  /// Hard bounds (mirrors Android PollingSettingsStore; A15: 0 threshold =
  /// always notify, capped at 7 days).
  static const int minIntervalMs = 1000;
  static const int maxIntervalMs = 86400000; // 24h
  static const int minThresholdMs = 0;
  static const int maxThresholdMs = 604800000; // 7d

  /// Clamp stored/legacy intervals into range. Pure, unit-tested.
  static int clampInterval(int ms) {
    if (ms < minIntervalMs) return minIntervalMs;
    if (ms > maxIntervalMs) return maxIntervalMs;
    return ms;
  }

  /// Clamp stored/legacy thresholds, falling back on out-of-range.
  /// Pure, unit-tested.
  static int clampThreshold(int ms, int fallback) {
    if (ms < minThresholdMs || ms > maxThresholdMs) return fallback;
    return ms;
  }

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
    _intervalMs = clampInterval(
        prefs.getInt(_kIntervalKey) ?? defaultIntervalMs);
    _thresholdSendMs = clampThreshold(
        prefs.getInt(_kThresholdSendKey) ?? defaultThresholdSendMs,
        defaultThresholdSendMs);
    _thresholdAdvancedMs = clampThreshold(
        prefs.getInt(_kThresholdAdvancedKey) ?? defaultThresholdAdvancedMs,
        defaultThresholdAdvancedMs);
    notifyListeners();
  }

  Future<void> setSettings({
    required int intervalMs,
    required int thresholdSendMs,
    required int thresholdAdvancedMs,
  }) async {
    if (intervalMs < minIntervalMs || intervalMs > maxIntervalMs) {
      throw ArgumentError(
          'intervalMs must be 1000..86400000 (got $intervalMs)');
    }
    if (thresholdSendMs < minThresholdMs ||
        thresholdSendMs > maxThresholdMs ||
        thresholdAdvancedMs < minThresholdMs ||
        thresholdAdvancedMs > maxThresholdMs) {
      throw ArgumentError('thresholds must be 0..604800000');
    }
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
