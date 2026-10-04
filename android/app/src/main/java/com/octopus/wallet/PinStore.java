package com.octopus.wallet;

import android.content.Context;
import android.content.SharedPreferences;

import androidx.security.crypto.EncryptedSharedPreferences;
import androidx.security.crypto.MasterKey;

public final class PinStore {
    private static final String PREFS_NAME = "pin_store";
    private static final String KEY_DEFAULT_PIN = "default_pin";
    private static volatile String cachedDefaultPin = "";

    private PinStore() {
    }

    public static void setDefaultPin(Context context, String pin) {
        String normalized = pin == null ? "" : pin.trim();
        cachedDefaultPin = normalized;
        getPrefs(context).edit().putString(KEY_DEFAULT_PIN, normalized).apply();
    }

    public static String getDefaultPin(Context context) {
        if (cachedDefaultPin != null && !cachedDefaultPin.isEmpty()) {
            return cachedDefaultPin;
        }
        String persisted = getPrefs(context).getString(KEY_DEFAULT_PIN, "");
        cachedDefaultPin = persisted == null ? "" : persisted;
        return cachedDefaultPin;
    }

    public static void clear(Context context) {
        cachedDefaultPin = "";
        getPrefs(context).edit().remove(KEY_DEFAULT_PIN).apply();
    }

    private static SharedPreferences getPrefs(Context context) {
        Context appCtx = context.getApplicationContext();
        try {
            MasterKey masterKey = new MasterKey.Builder(appCtx)
                    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                    .build();
            return EncryptedSharedPreferences.create(
                    appCtx,
                    PREFS_NAME,
                    masterKey,
                    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            );
        } catch (Exception ignored) {
            return appCtx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        }
    }
}
