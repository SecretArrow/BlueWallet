package com.octopus.wallet;

import android.content.Context;
import android.content.SharedPreferences;

import java.security.SecureRandom;

/**
 * Persistent configuration store for the LocalWebServer feature.
 *
 * <p>Stores whether the server is enabled, the auth token, and the port.
 * Default: disabled, port 8420.</p>
 */
public final class LocalWebServerStore {

    private static final String PREFS = "local_web_server";
    private static final String KEY_ENABLED = "enabled";
    private static final String KEY_AUTH_TOKEN = "auth_token";
    public static final int PORT = 8420;

    private LocalWebServerStore() {}

    // ── Enabled / Disabled ────────────────────────────────────────────────

    /** Returns {@code true} if the local web server is enabled (default: {@code false}). */
    public static boolean isEnabled(Context context) {
        return prefs(context).getBoolean(KEY_ENABLED, false);
    }

    /** Enable or disable the local web server. */
    public static void setEnabled(Context context, boolean enabled) {
        prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply();
    }

    // ── Auth token ────────────────────────────────────────────────────────

    /**
     * Returns the Bearer auth token, generating and persisting one if it does not exist.
     *
     * <p>The token is a 32-byte cryptographically random hex string.</p>
     */
    public static String getAuthToken(Context context) {
        SharedPreferences p = prefs(context);
        String token = p.getString(KEY_AUTH_TOKEN, null);
        if (token == null || token.isEmpty()) {
            token = generateToken();
            p.edit().putString(KEY_AUTH_TOKEN, token).apply();
        }
        return token;
    }

    /** Regenerates the auth token.  Old token is immediately invalidated. */
    public static String regenerateToken(Context context) {
        String token = generateToken();
        prefs(context).edit().putString(KEY_AUTH_TOKEN, token).apply();
        return token;
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    private static SharedPreferences prefs(Context context) {
        return context.getApplicationContext()
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private static String generateToken() {
        byte[] bytes = new byte[32];
        new SecureRandom().nextBytes(bytes);
        StringBuilder sb = new StringBuilder(64);
        for (byte b : bytes) {
            sb.append(String.format("%02x", b));
        }
        return sb.toString();
    }
}
