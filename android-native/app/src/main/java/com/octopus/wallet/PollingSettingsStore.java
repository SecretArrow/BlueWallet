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

    /** Hard bounds: below 1s burns battery / crashes schedulers. */
    public static final long MIN_INTERVAL_MS = 1_000L;
    public static final long MAX_INTERVAL_MS = 86_400_000L; // 24h
    /** Threshold bounds (A15: 0 = always notify, capped at 7 days). */
    public static final long MIN_THRESHOLD_MS = 0L;
    public static final long MAX_THRESHOLD_MS = 604_800_000L; // 7d

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
        return clampInterval(getSafeLong(context, KEY_INTERVAL, DEFAULT_INTERVAL_MS));
    }

    public static void setIntervalMs(Context context, long ms) {
        if (ms < MIN_INTERVAL_MS || ms > MAX_INTERVAL_MS) {
            throw new IllegalArgumentException(
                    "Polling interval must be 1000..86400000 ms (got " + ms + ")");
        }
        getPrefs(context).edit().putLong(KEY_INTERVAL, ms).apply();
    }

    /** Clamp stored/legacy values into range. Package-visible for tests. */
    static long clampInterval(long ms) {
        if (ms < MIN_INTERVAL_MS) return MIN_INTERVAL_MS;
        if (ms > MAX_INTERVAL_MS) return MAX_INTERVAL_MS;
        return ms;
    }

    /** Clamp stored/legacy values into range. Package-visible for tests. */
    static long clampThreshold(long ms, long fallback) {
        if (ms < MIN_THRESHOLD_MS || ms > MAX_THRESHOLD_MS) return fallback;
        return ms;
    }

    public static long getThresholdSendMs(Context context) {
        return clampThreshold(
                getSafeLong(context, KEY_THRESHOLD_SEND, DEFAULT_THRESHOLD_SEND_MS),
                DEFAULT_THRESHOLD_SEND_MS);
    }

    public static void setThresholdSendMs(Context context, long ms) {
        if (ms < MIN_THRESHOLD_MS || ms > MAX_THRESHOLD_MS) {
            throw new IllegalArgumentException(
                    "Threshold must be 0..604800000 ms (got " + ms + ")");
        }
        getPrefs(context).edit().putLong(KEY_THRESHOLD_SEND, ms).apply();
    }

    public static long getThresholdAdvancedMs(Context context) {
        return clampThreshold(
                getSafeLong(context, KEY_THRESHOLD_ADVANCED, DEFAULT_THRESHOLD_ADVANCED_MS),
                DEFAULT_THRESHOLD_ADVANCED_MS);
    }

    public static void setThresholdAdvancedMs(Context context, long ms) {
        if (ms < MIN_THRESHOLD_MS || ms > MAX_THRESHOLD_MS) {
            throw new IllegalArgumentException(
                    "Threshold must be 0..604800000 ms (got " + ms + ")");
        }
        getPrefs(context).edit().putLong(KEY_THRESHOLD_ADVANCED, ms).apply();
    }
}
