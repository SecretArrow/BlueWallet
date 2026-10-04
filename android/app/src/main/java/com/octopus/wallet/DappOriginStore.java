package com.octopus.wallet;

import android.content.Context;
import android.content.SharedPreferences;

import java.util.Arrays;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;

public final class DappOriginStore {
    private static final String PREFS = "dapp_origin_prefs";
    private static final String KEY_ALLOWED = "allowed_origins";
    private static final String KEY_INIT = "initialized";

    private DappOriginStore() {
    }

    public static Set<String> getAllowedOrigins(Context context) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        ensureInitialized(prefs);
        Set<String> stored = prefs.getStringSet(KEY_ALLOWED, defaultOrigins());
        return new HashSet<>(stored == null ? defaultOrigins() : stored);
    }

    public static void setAllowedOrigins(Context context, Set<String> origins) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        HashSet<String> normalized = new HashSet<>();
        if (origins != null) {
            for (String origin : origins) {
                String host = normalizeHost(origin);
                if (!host.isEmpty()) {
                    normalized.add(host);
                }
            }
        }
        prefs.edit().putStringSet(KEY_ALLOWED, normalized).apply();
    }

    public static void addOrigin(Context context, String origin) {
        Set<String> origins = getAllowedOrigins(context);
        String host = normalizeHost(origin);
        if (!host.isEmpty()) {
            origins.add(host);
            setAllowedOrigins(context, origins);
        }
    }

    public static void removeOrigin(Context context, String origin) {
        Set<String> origins = getAllowedOrigins(context);
        String host = normalizeHost(origin);
        if (!host.isEmpty()) {
            origins.remove(host);
            setAllowedOrigins(context, origins);
        }
    }

    public static void resetToDefault(Context context) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        prefs.edit()
                .putStringSet(KEY_ALLOWED, defaultOrigins())
                .putBoolean(KEY_INIT, true)
                .apply();
    }

    public static String normalizeHost(String origin) {
        if (origin == null) {
            return "";
        }
        String host = origin.trim().toLowerCase(Locale.US);
        if (host.startsWith("http://")) {
            host = host.substring(7);
        } else if (host.startsWith("https://")) {
            host = host.substring(8);
        }
        int slashIndex = host.indexOf('/');
        if (slashIndex >= 0) {
            host = host.substring(0, slashIndex);
        }
        int queryIndex = host.indexOf('?');
        if (queryIndex >= 0) {
            host = host.substring(0, queryIndex);
        }
        int hashIndex = host.indexOf('#');
        if (hashIndex >= 0) {
            host = host.substring(0, hashIndex);
        }
        return host.trim();
    }

    private static void ensureInitialized(SharedPreferences prefs) {
        if (prefs.getBoolean(KEY_INIT, false)) {
            return;
        }
        prefs.edit()
                .putStringSet(KEY_ALLOWED, defaultOrigins())
                .putBoolean(KEY_INIT, true)
                .apply();
    }

    private static HashSet<String> defaultOrigins() {
        return new HashSet<>(Arrays.asList(
                "devnet.octrascan.io",
                "octrascan.io",
                "localhost",
                "127.0.0.1"
        ));
    }
}
