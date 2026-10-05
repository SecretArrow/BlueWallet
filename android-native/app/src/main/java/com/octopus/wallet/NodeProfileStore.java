package com.octopus.wallet;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

public final class NodeProfileStore {
    private static final String PREFS = "node_profiles";
    private static final String KEY_ITEMS = "items";
    private static final String KEY_SELECTED = "selected";

    public static final class NodeProfile {
        public final String name;
        public final String rpcUrl;
        public final String explorerUrl;

        public NodeProfile(String name, String rpcUrl, String explorerUrl) {
            this.name = name;
            this.rpcUrl = rpcUrl;
            this.explorerUrl = explorerUrl;
        }
    }

    private NodeProfileStore() {
    }

    public static void ensureDefault(Context context, String rpcUrl, String explorerUrl) {
        SharedPreferences prefs = prefs(context);
        List<NodeProfile> items = getProfiles(context);
        if (items.isEmpty()) {
            // Pre-populate Mainnet (per octrascan.io/docs.html) as active default.
            items.add(new NodeProfile("Octra Mainnet",
                    UrlSecurityValidator.MAINNET_RPC,
                    UrlSecurityValidator.MAINNET_EXPLORER));

            // Pre-populate Devnet as built-in secondary network.
            items.add(new NodeProfile("Octra Devnet",
                    UrlSecurityValidator.DEVNET_RPC,
                    UrlSecurityValidator.DEVNET_EXPLORER));

            saveProfiles(context, items, "Octra Mainnet");
            return;
        }

        String selected = prefs.getString(KEY_SELECTED, "");
        if (selected == null || selected.isEmpty() || findByName(items, selected) == null) {
            saveProfiles(context, items, items.get(0).name);
        }
    }

    public static List<NodeProfile> getProfiles(Context context) {
        SharedPreferences prefs = prefs(context);
        String raw = prefs.getString(KEY_ITEMS, "[]");
        List<NodeProfile> list = new ArrayList<>();
        try {
            JSONArray array = new JSONArray(raw);
            for (int i = 0; i < array.length(); i++) {
                JSONObject item = array.optJSONObject(i);
                if (item == null) {
                    continue;
                }
                String name = item.optString("name", "").trim();
                String rpc = item.optString("rpc", "").trim();
                String explorer = item.optString("explorer", "").trim();
                if (!name.isEmpty() && !rpc.isEmpty()) {
                    list.add(new NodeProfile(name, rpc, explorer));
                }
            }
        } catch (Exception ignored) {
        }
        return list;
    }

    public static String getSelectedName(Context context) {
        return prefs(context).getString(KEY_SELECTED, "");
    }

    public static void setSelectedName(Context context, String name) {
        prefs(context).edit().putString(KEY_SELECTED, name).apply();
    }

    public static NodeProfile addProfile(Context context, String preferredName, String rpcUrl, String explorerUrl) {
        List<NodeProfile> list = getProfiles(context);
        String base = sanitizeName(preferredName == null || preferredName.isEmpty() ? "Node" : preferredName);
        if (base.isEmpty()) {
            base = "Node";
        }
        String candidate = uniqueName(list, base);
        String normalizedRpc = UrlSecurityValidator.normalizeRpcUrl(rpcUrl);
        String normalizedExplorer = UrlSecurityValidator.normalizeExplorerUrl(explorerUrl);
        if (normalizedRpc == null || normalizedRpc.trim().isEmpty()) {
            normalizedRpc = UrlSecurityValidator.DEFAULT_RPC;
        }
        if (normalizedExplorer == null || normalizedExplorer.trim().isEmpty()) {
            normalizedExplorer = UrlSecurityValidator.DEFAULT_EXPLORER;
        }
        NodeProfile added = new NodeProfile(candidate, normalizedRpc, normalizedExplorer);
        list.add(added);
        saveProfiles(context, list, candidate);
        return added;
    }

    public static boolean removeProfile(Context context, String name) {
        List<NodeProfile> list = getProfiles(context);
        if (list.size() <= 1) {
            return false;
        }
        NodeProfile target = findByName(list, name);
        if (target == null) {
            return false;
        }
        list.remove(target);
        String next = list.get(0).name;
        saveProfiles(context, list, next);
        return true;
    }

    public static void updateProfile(Context context, String name, String rpcUrl, String explorerUrl) {
        List<NodeProfile> list = getProfiles(context);
        String normalizedRpc = UrlSecurityValidator.normalizeRpcUrl(rpcUrl);
        String normalizedExplorer = UrlSecurityValidator.normalizeExplorerUrl(explorerUrl);
        if (normalizedRpc == null || normalizedRpc.trim().isEmpty()) {
            normalizedRpc = UrlSecurityValidator.DEFAULT_RPC;
        }
        if (normalizedExplorer == null || normalizedExplorer.trim().isEmpty()) {
            normalizedExplorer = UrlSecurityValidator.DEFAULT_EXPLORER;
        }
        for (int i = 0; i < list.size(); i++) {
            NodeProfile item = list.get(i);
            if (item.name.equals(name)) {
                list.set(i, new NodeProfile(name, normalizedRpc, normalizedExplorer));
                saveProfiles(context, list, name);
                return;
            }
        }
    }

    public static NodeProfile findByName(List<NodeProfile> list, String name) {
        if (list == null || name == null) return null;
        for (NodeProfile item : list) {
            if (item != null && name.equals(item.name)) {
                return item;
            }
        }
        return null;
    }

    private static void saveProfiles(Context context, List<NodeProfile> list, String selected) {
        JSONArray array = new JSONArray();
        for (NodeProfile item : list) {
            JSONObject row = new JSONObject();
            try {
                row.put("name", item.name);
                row.put("rpc", item.rpcUrl);
                row.put("explorer", item.explorerUrl);
                array.put(row);
            } catch (Exception ignored) {
            }
        }
        prefs(context).edit()
                .putString(KEY_ITEMS, array.toString())
                .putString(KEY_SELECTED, selected)
                .apply();
    }

    /**
     * Deduplicate a display name ("X", "X 2", "X 3", …). Pure and unit-tested.
     */
    static String uniqueName(List<NodeProfile> existing, String base) {
        String candidate = base;
        int index = 2;
        while (findByName(existing, candidate) != null) {
            candidate = base + " " + index;
            index++;
        }
        return candidate;
    }

    /** Package-visible for tests. */
    static String sanitizeName(String input) {
        if (input == null) return "";
        return input.replaceAll("[^A-Za-z0-9 _-]", "").trim();
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }
}
