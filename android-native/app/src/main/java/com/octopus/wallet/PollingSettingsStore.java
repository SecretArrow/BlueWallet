package com.octopus.wallet;

import android.content.Context;
import android.content.SharedPreferences;

public final class PollingSettingsStore {
    private static final String PREFS = "github.com.maragung.octopus_wallet_preferences";
    private static final String KEY_INTERVAL = "flutter.polling_interval_ms";
    private static final String KEY_THRESHOLD_SEND = "flutter.threshold_send_ms";
    private static final String KEY_THRESHOLD_ADVANCED = "flutter.threshold_advanced_ms";

    public static final long DEFAULT_INTERVAL_MS = 5000L;
    public static final long DEFAULT_THRESHOLD_SEND_MS = 300_000L; // 5m
    public static final long DEFAULT_THRESHOLD_ADVANCED_MS = 600_000L; // 10m

    private PollingSettingsStore() {}

    private static SharedPreferences getPrefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private static long getSafeLong(Context context, String key, long defaultValue) {
        try {
            Object val = getPrefs(context).getAll().get(key);
            if (val == null) {
                return defaultValue;
            }
            if (val instanceof Long) {
                return (Long) val;
            }
            if (val instanceof Integer) {
                return ((Integer) val).longValue();
            }
            if (val instanceof String) {
                return Long.parseLong((String) val);
            }
            if (val instanceof Float) {
                return ((Float) val).longValue();
            }
            if (val instanceof Double) {
                return ((Double) val).longValue();
            }
            return defaultValue;
        } catch (Exception e) {
            return defaultValue;
        }
    }

    public static long getIntervalMs(Context context) {
        return getSafeLong(context, KEY_INTERVAL, DEFAULT_INTERVAL_MS);
    }

    public static void setIntervalMs(Context context, long ms) {
        getPrefs(context).edit().putLong(KEY_INTERVAL, ms).apply();
    }

    public static long getThresholdSendMs(Context context) {
        return getSafeLong(context, KEY_THRESHOLD_SEND, DEFAULT_THRESHOLD_SEND_MS);
    }

    public static void setThresholdSendMs(Context context, long ms) {
        getPrefs(context).edit().putLong(KEY_THRESHOLD_SEND, ms).apply();
    }

    public static long getThresholdAdvancedMs(Context context) {
        return getSafeLong(context, KEY_THRESHOLD_ADVANCED, DEFAULT_THRESHOLD_ADVANCED_MS);
    }

    public static void setThresholdAdvancedMs(Context context, long ms) {
        getPrefs(context).edit().putLong(KEY_THRESHOLD_ADVANCED, ms).apply();
    }
}
