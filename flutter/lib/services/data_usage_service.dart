import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to track network data usage for the app itself.
class DataUsageService {
  static const String _prefsName = 'data_usage_prefs';
  static const String _keyUsageHistory = 'usage_history';
  static const String _keySessionStartRx = 'session_start_rx';
  static const String _keySessionStartTx = 'session_start_tx';
  static const String _keySessionStartTime = 'session_start_time';

  static DataUsageService? _instance;
  static DataUsageService get instance => _instance ??= DataUsageService._();

  DataUsageService._();

  /// Start a new tracking session.
  Future<void> startSession() async {
    final prefs = await SharedPreferences.getInstance();
    // Note: Flutter doesn't have direct access to TrafficStats like Android
    // We'll track based on API calls and manual recording
    await prefs.setInt(_keySessionStartRx, 0);
    await prefs.setInt(_keySessionStartTx, 0);
    await prefs.setInt(
        _keySessionStartTime, DateTime.now().millisecondsSinceEpoch);
  }

  /// Record data usage for a specific transaction.
  Future<void> recordTransaction(
    String transactionType,
    String description, {
    int rxBytes = 0,
    int txBytes = 0,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final sessionStartTime = prefs.getInt(_keySessionStartTime) ??
        DateTime.now().millisecondsSinceEpoch;

    try {
      final history = await getUsageHistory();

      final entry = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'type': transactionType,
        'description': description,
        'rx_bytes': rxBytes,
        'tx_bytes': txBytes,
        'total_bytes': rxBytes + txBytes,
        'session_duration_ms':
            DateTime.now().millisecondsSinceEpoch - sessionStartTime,
      };

      history.add(entry);

      // Keep only last 100 entries
      if (history.length > 100) {
        history.removeRange(0, history.length - 100);
      }

      await prefs.setString(_keyUsageHistory, jsonEncode(history));
    } catch (e) {
      // Use debugPrint instead of print to avoid logging in release builds
      assert(() {
        debugPrint('Error recording data usage: $e');
        return true;
      }());
    }

    // Reset session counters
    await startSession();
  }

  /// Get total data usage.
  Future<DataUsage> getTotalUsage() async {
    final history = await getUsageHistory();
    int totalRx = 0;
    int totalTx = 0;

    for (final entry in history) {
      totalRx += (entry['rx_bytes'] as int?) ?? 0;
      totalTx += (entry['tx_bytes'] as int?) ?? 0;
    }

    return DataUsage(rxBytes: totalRx, txBytes: totalTx);
  }

  /// Get current session data usage.
  Future<DataUsage> getSessionUsage() async {
    final history = await getUsageHistory();
    final sessionStartTime =
        (await SharedPreferences.getInstance()).getInt(_keySessionStartTime) ??
            0;

    int sessionRx = 0;
    int sessionTx = 0;

    for (final entry in history) {
      final timestamp = (entry['timestamp'] as int?) ?? 0;
      if (timestamp >= sessionStartTime) {
        sessionRx += (entry['rx_bytes'] as int?) ?? 0;
        sessionTx += (entry['tx_bytes'] as int?) ?? 0;
      }
    }

    return DataUsage(rxBytes: sessionRx, txBytes: sessionTx);
  }

  /// Get usage history as a list.
  Future<List<DataUsageEntry>> getUsageHistoryList() async {
    final history = await getUsageHistory();
    final entries = <DataUsageEntry>[];

    // Return in reverse order (newest first)
    for (var i = history.length - 1; i >= 0; i--) {
      final entry = history[i];
      entries.add(DataUsageEntry(
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            (entry['timestamp'] as int?) ?? 0),
        type: (entry['type'] as String?) ?? 'Unknown',
        description: (entry['description'] as String?) ?? '',
        rxBytes: (entry['rx_bytes'] as int?) ?? 0,
        txBytes: (entry['tx_bytes'] as int?) ?? 0,
        totalBytes: (entry['total_bytes'] as int?) ?? 0,
        sessionDurationMs: (entry['session_duration_ms'] as int?) ?? 0,
      ));
    }

    return entries;
  }

  /// Clear all usage history.
  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUsageHistory);
    await startSession();
  }

  Future<List<Map<String, dynamic>>> getUsageHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString(_keyUsageHistory) ?? '[]';
    try {
      final List<dynamic> decoded = jsonDecode(historyJson);
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      // Use debugPrint instead of print
      assert(() {
        debugPrint('Error reading usage history: $e');
        return true;
      }());
      return [];
    }
  }
}

/// Data usage container.
class DataUsage {
  final int rxBytes;
  final int txBytes;
  int get totalBytes => rxBytes + txBytes;

  DataUsage({required this.rxBytes, required this.txBytes});

  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get formattedRx => formatBytes(rxBytes);
  String get formattedTx => formatBytes(txBytes);
  String get formattedTotal => formatBytes(totalBytes);
}

/// Single usage entry.
class DataUsageEntry {
  final DateTime timestamp;
  final String type;
  final String description;
  final int rxBytes;
  final int txBytes;
  final int totalBytes;
  final int sessionDurationMs;

  DataUsageEntry({
    required this.timestamp,
    required this.type,
    required this.description,
    required this.rxBytes,
    required this.txBytes,
    required this.totalBytes,
    required this.sessionDurationMs,
  });

  String get formattedTime {
    return '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
  }

  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get formattedRx => formatBytes(rxBytes);
  String get formattedTx => formatBytes(txBytes);
  String get formattedTotal => formatBytes(totalBytes);
}
