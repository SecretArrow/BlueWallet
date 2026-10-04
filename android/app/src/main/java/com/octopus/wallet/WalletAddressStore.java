package com.octopus.wallet;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONObject;

import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;

public final class WalletAddressStore {
    private static final String PREFS = "wallet_address_store";
    private static final String KEY_MAP = "wallet_address_map";

    private WalletAddressStore() {
    }

    public static synchronized void putAddress(Context context, String walletId, String address) {
        String id = walletId == null ? "" : walletId.trim();
        String addr = address == null ? "" : address.trim();
        if (id.isEmpty() || addr.isEmpty()) {
            return;
        }
        Map<String, String> all = getAllAddresses(context);
        all.put(id, addr);
        persist(context, all);
    }

    public static synchronized String getAddress(Context context, String walletId) {
        String id = walletId == null ? "" : walletId.trim();
        if (id.isEmpty()) return "";
        Map<String, String> all = getAllAddresses(context);
        String addr = all.get(id);
        return addr == null ? "" : addr;
    }

    public static synchronized void removeAddress(Context context, String walletId) {
        String id = walletId == null ? "" : walletId.trim();
        if (id.isEmpty()) return;
        Map<String, String> all = getAllAddresses(context);
        if (all.remove(id) != null) {
            persist(context, all);
        }
    }

    public static synchronized Map<String, String> getAllAddresses(Context context) {
        Map<String, String> out = new HashMap<>();
        try {
            String raw = context.getApplicationContext()
                    .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .getString(KEY_MAP, "{}");
            JSONObject obj = new JSONObject(raw == null ? "{}" : raw);
            Iterator<String> keys = obj.keys();
            while (keys.hasNext()) {
                String key = keys.next();
                String value = obj.optString(key, "").trim();
                if (!key.trim().isEmpty() && !value.isEmpty()) {
                    out.put(key, value);
                }
            }
        } catch (Exception ignored) {
        }
        return out;
    }

    private static void persist(Context context, Map<String, String> all) {
        JSONObject obj = new JSONObject();
        try {
            for (Map.Entry<String, String> entry : all.entrySet()) {
                obj.put(entry.getKey(), entry.getValue());
            }
        } catch (Exception ignored) {
        }
        SharedPreferences prefs = context.getApplicationContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        prefs.edit().putString(KEY_MAP, obj.toString()).apply();
    }
}
