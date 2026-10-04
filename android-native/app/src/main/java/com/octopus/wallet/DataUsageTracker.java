package com.octopus.wallet;

import android.content.Context;
import android.content.SharedPreferences;
import android.net.TrafficStats;

import org.json.JSONArray;
import org.json.JSONObject;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;

/**
 * Tracks network data usage for the app itself.
 * Records data usage per transaction/session.
 */
public class DataUsageTracker {
    private static final String PREFS_NAME = "data_usage_prefs";
    private static final String KEY_USAGE_HISTORY = "usage_history";
    private static final String KEY_LAST_RX_BYTES = "last_rx_bytes";
    private static final String KEY_LAST_TX_BYTES = "last_tx_bytes";
    private static final String KEY_SESSION_START_RX = "session_start_rx";
    private static final String KEY_SESSION_START_TX = "session_start_tx";
    private static final String KEY_SESSION_START_TIME = "session_start_time";

    private final Context context;
    private final SharedPreferences prefs;
    private final int uid;

    public DataUsageTracker(Context context) {
        this.context = context.getApplicationContext();
        this.prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        this.uid = android.os.Process.myUid();
    }

    /**
     * Start a new tracking session.
     */
    public void startSession() {
        long currentRx = TrafficStats.getUidRxBytes(uid);
        long currentTx = TrafficStats.getUidTxBytes(uid);
        
        prefs.edit()
            .putLong(KEY_SESSION_START_RX, currentRx)
            .putLong(KEY_SESSION_START_TX, currentTx)
            .putLong(KEY_SESSION_START_TIME, System.currentTimeMillis())
            .apply();
    }

    /**
     * Record data usage for a specific transaction.
     */
    public void recordTransaction(String transactionType, String description) {
        // Input validation
        if (transactionType == null || transactionType.trim().isEmpty()) {
            transactionType = "Unknown";
        }
        if (description == null) {
            description = "";
        }
        // Limit description length to prevent excessive storage
        if (description.length() > 200) {
            description = description.substring(0, 200);
        }

        long sessionStartRx = prefs.getLong(KEY_SESSION_START_RX, 0);
        long sessionStartTx = prefs.getLong(KEY_SESSION_START_TX, 0);
        long sessionStartTime = prefs.getLong(KEY_SESSION_START_TIME, System.currentTimeMillis());

        long currentRx = TrafficStats.getUidRxBytes(uid);
        long currentTx = TrafficStats.getUidTxBytes(uid);

        long rxBytes = Math.max(0, currentRx - sessionStartRx);
        long txBytes = Math.max(0, currentTx - sessionStartTx);

        try {
            JSONArray history = getUsageHistory();
            JSONObject entry = new JSONObject();
            entry.put("timestamp", System.currentTimeMillis());
            entry.put("type", transactionType);
            entry.put("description", description);
            entry.put("rx_bytes", rxBytes);
            entry.put("tx_bytes", txBytes);
            entry.put("total_bytes", rxBytes + txBytes);
            entry.put("session_duration_ms", System.currentTimeMillis() - sessionStartTime);

            history.put(entry);

            // Keep only last 100 entries
            if (history.length() > 100) {
                JSONArray trimmed = new JSONArray();
                for (int i = history.length() - 100; i < history.length(); i++) {
                    trimmed.put(history.get(i));
                }
                history = trimmed;
            }

            prefs.edit().putString(KEY_USAGE_HISTORY, history.toString()).apply();
        } catch (Exception e) {
            // Use proper logging instead of printStackTrace
            android.util.Log.e("DataUsageTracker", "Error recording transaction", e);
        }

        // Reset session counters
        startSession();
    }

    /**
     * Get total data usage since app installation.
     */
    public DataUsage getTotalUsage() {
        long totalRx = TrafficStats.getUidRxBytes(uid);
        long totalTx = TrafficStats.getUidTxBytes(uid);
        
        if (totalRx == TrafficStats.UNSUPPORTED || totalTx == TrafficStats.UNSUPPORTED) {
            return new DataUsage(0, 0);
        }
        
        return new DataUsage(totalRx, totalTx);
    }

    /**
     * Get current session data usage.
     */
    public DataUsage getSessionUsage() {
        long sessionStartRx = prefs.getLong(KEY_SESSION_START_RX, 0);
        long sessionStartTx = prefs.getLong(KEY_SESSION_START_TX, 0);
        
        long currentRx = TrafficStats.getUidRxBytes(uid);
        long currentTx = TrafficStats.getUidTxBytes(uid);
        
        long rxBytes = Math.max(0, currentRx - sessionStartRx);
        long txBytes = Math.max(0, currentTx - sessionStartTx);
        
        return new DataUsage(rxBytes, txBytes);
    }

    /**
     * Get usage history as a list.
     */
    public List<DataUsageEntry> getUsageHistoryList() {
        List<DataUsageEntry> entries = new ArrayList<>();
        try {
            JSONArray history = getUsageHistory();
            for (int i = history.length() - 1; i >= 0; i--) {
                JSONObject obj = history.getJSONObject(i);
                entries.add(new DataUsageEntry(
                    obj.getLong("timestamp"),
                    obj.optString("type", "Unknown"),
                    obj.optString("description", ""),
                    obj.optLong("rx_bytes", 0),
                    obj.optLong("tx_bytes", 0),
                    obj.optLong("total_bytes", 0),
                    obj.optLong("session_duration_ms", 0)
                ));
            }
        } catch (Exception e) {
            android.util.Log.e("DataUsageTracker", "Error reading history", e);
        }
        return entries;
    }

    /**
     * Clear all usage history.
     */
    public void clearHistory() {
        prefs.edit().remove(KEY_USAGE_HISTORY).apply();
        startSession();
    }

    private JSONArray getUsageHistory() {
        String historyJson = prefs.getString(KEY_USAGE_HISTORY, "[]");
        try {
            return new JSONArray(historyJson);
        } catch (Exception e) {
            return new JSONArray();
        }
    }

    /**
     * Data usage container.
     */
    public static class DataUsage {
        public final long rxBytes;
        public final long txBytes;
        public final long totalBytes;

        public DataUsage(long rxBytes, long txBytes) {
            this.rxBytes = rxBytes;
            this.txBytes = txBytes;
            this.totalBytes = rxBytes + txBytes;
        }

        public String formatBytes(long bytes) {
            if (bytes < 1024) return bytes + " B";
            if (bytes < 1024 * 1024) return String.format(Locale.US, "%.2f KB", bytes / 1024.0);
            if (bytes < 1024 * 1024 * 1024) return String.format(Locale.US, "%.2f MB", bytes / (1024.0 * 1024.0));
            return String.format(Locale.US, "%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0));
        }

        public String getFormattedRx() { return formatBytes(rxBytes); }
        public String getFormattedTx() { return formatBytes(txBytes); }
        public String getFormattedTotal() { return formatBytes(totalBytes); }
    }

    /**
     * Single usage entry.
     */
    public static class DataUsageEntry {
        public final long timestamp;
        public final String type;
        public final String description;
        public final long rxBytes;
        public final long txBytes;
        public final long totalBytes;
        public final long sessionDurationMs;

        public DataUsageEntry(long timestamp, String type, String description,
                            long rxBytes, long txBytes, long totalBytes, long sessionDurationMs) {
            this.timestamp = timestamp;
            this.type = type;
            this.description = description;
            this.rxBytes = rxBytes;
            this.txBytes = txBytes;
            this.totalBytes = totalBytes;
            this.sessionDurationMs = sessionDurationMs;
        }

        public String getFormattedTime() {
            SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault());
            return sdf.format(new Date(timestamp));
        }

        public String formatBytes(long bytes) {
            if (bytes < 1024) return bytes + " B";
            if (bytes < 1024 * 1024) return String.format(Locale.US, "%.2f KB", bytes / 1024.0);
            if (bytes < 1024 * 1024 * 1024) return String.format(Locale.US, "%.2f MB", bytes / (1024.0 * 1024.0));
            return String.format(Locale.US, "%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0));
        }

        public String getFormattedRx() { return formatBytes(rxBytes); }
        public String getFormattedTx() { return formatBytes(txBytes); }
        public String getFormattedTotal() { return formatBytes(totalBytes); }
    }
}
