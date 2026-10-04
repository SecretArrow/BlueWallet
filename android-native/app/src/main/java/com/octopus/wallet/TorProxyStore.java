package com.octopus.wallet;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Log;
import org.json.JSONArray;
import org.json.JSONObject;
import java.net.InetSocketAddress;
import java.net.Proxy;
import java.util.ArrayList;
import java.util.List;

public final class TorProxyStore {

    private static final String TAG = "TorProxyStore";
    private static final String PREFS = "tor_proxy_settings";
    private static final String KEY_ENABLED = "enabled";
    private static final String KEY_ACTIVE_HOST = "active_host";
    private static final String KEY_ACTIVE_PORT = "active_port";
    private static final String KEY_ACTIVE_TYPE = "active_type"; // "SOCKS" or "HTTP"
    private static final String KEY_SERVERS_LIST = "servers_list";

    private TorProxyStore() {}

    public static boolean isEnabled(Context context) {
        return prefs(context).getBoolean(KEY_ENABLED, false);
    }

    public static void setEnabled(Context context, boolean enabled) {
        prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply();
    }

    public static Proxy getActiveProxy(Context context) {
        SharedPreferences p = prefs(context);
        String host = p.getString(KEY_ACTIVE_HOST, "127.0.0.1");
        int port = p.getInt(KEY_ACTIVE_PORT, 9050);
        String typeStr = p.getString(KEY_ACTIVE_TYPE, "SOCKS");

        try {
            Proxy.Type type = "HTTP".equalsIgnoreCase(typeStr) ? Proxy.Type.HTTP : Proxy.Type.SOCKS;
            // Use createUnresolved to prevent local DNS leak! Remote proxy will perform DNS resolution.
            return new Proxy(type, InetSocketAddress.createUnresolved(host, port));
        } catch (Exception e) {
            Log.e(TAG, "Failed to create proxy object", e);
            return null;
        }
    }

    public static ProxyConfig getActiveProxyConfig(Context context) {
        SharedPreferences p = prefs(context);
        String host = p.getString(KEY_ACTIVE_HOST, "127.0.0.1");
        int port = p.getInt(KEY_ACTIVE_PORT, 9050);
        String typeStr = p.getString(KEY_ACTIVE_TYPE, "SOCKS");
        return new ProxyConfig("Active", host, port, typeStr, false);
    }

    public static void setActiveProxy(Context context, String host, int port, String type) {
        prefs(context).edit()
                .putString(KEY_ACTIVE_HOST, host)
                .putInt(KEY_ACTIVE_PORT, port)
                .putString(KEY_ACTIVE_TYPE, type)
                .apply();
    }

    public static List<ProxyConfig> getProxyServers(Context context) {
        SharedPreferences p = prefs(context);
        String listJson = p.getString(KEY_SERVERS_LIST, null);
        List<ProxyConfig> list = new ArrayList<>();

        if (listJson == null || listJson.isEmpty()) {
            // Load default servers
            list.add(new ProxyConfig("Orbot SOCKS (Lokal)", "127.0.0.1", 9050, "SOCKS", true));
            list.add(new ProxyConfig("Orbot HTTP (Lokal)", "127.0.0.1", 8118, "HTTP", true));
            list.add(new ProxyConfig("Public Tor Proxy (Free)", "173.249.49.52", 9050, "SOCKS", true));
            list.add(new ProxyConfig("SOCKS5 Proxy (Fast)", "45.140.13.125", 9050, "SOCKS", true));
            saveProxyServers(context, list);
        } else {
            try {
                JSONArray arr = new JSONArray(listJson);
                for (int i = 0; i < arr.length(); i++) {
                    JSONObject obj = arr.getJSONObject(i);
                    list.add(new ProxyConfig(
                            obj.getString("name"),
                            obj.getString("host"),
                            obj.getInt("port"),
                            obj.getString("type"),
                            obj.optBoolean("isDefault", false)
                    ));
                }
            } catch (Exception e) {
                Log.e(TAG, "Error loading proxy list JSON", e);
            }
        }
        return list;
    }

    public static void saveProxyServers(Context context, List<ProxyConfig> list) {
        try {
            JSONArray arr = new JSONArray();
            for (ProxyConfig c : list) {
                JSONObject obj = new JSONObject();
                obj.put("name", c.name);
                obj.put("host", c.host);
                obj.put("port", c.port);
                obj.put("type", c.type);
                obj.put("isDefault", c.isDefault);
                arr.put(obj);
            }
            prefs(context).edit().putString(KEY_SERVERS_LIST, arr.toString()).apply();
        } catch (Exception e) {
            Log.e(TAG, "Error saving proxy list JSON", e);
        }
    }

    public static void addProxyServer(Context context, ProxyConfig config) {
        List<ProxyConfig> list = getProxyServers(context);
        list.add(config);
        saveProxyServers(context, list);
    }

    public static boolean removeProxyServer(Context context, String host, int port) {
        List<ProxyConfig> list = getProxyServers(context);
        boolean removed = false;
        for (int i = 0; i < list.size(); i++) {
            ProxyConfig c = list.get(i);
            if (c.host.equalsIgnoreCase(host) && c.port == port) {
                if (c.isDefault) {
                    return false; // Prevent removing default servers
                }
                list.remove(i);
                removed = true;
                break;
            }
        }
        if (removed) {
            saveProxyServers(context, list);
        }
        return removed;
    }

    private static SharedPreferences prefs(Context context) {
        return context.getApplicationContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    public static class ProxyConfig {
        public final String name;
        public final String host;
        public final int port;
        public final String type; // "SOCKS" or "HTTP"
        public final boolean isDefault;

        public ProxyConfig(String name, String host, int port, String type, boolean isDefault) {
            this.name = name;
            this.host = host;
            this.port = port;
            this.type = type;
            this.isDefault = isDefault;
        }
    }
}
