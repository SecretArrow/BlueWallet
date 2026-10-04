package com.octopus.wallet;

import android.content.Context;
import android.content.SharedPreferences;

import java.io.File;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

public final class WalletProfileStore {
    private static final String PREFS = "wallet_profiles";
    private static final String KEY_ORDERED_IDS = "ordered_ids";
    private static final String KEY_SELECTED_ID = "selected_id";
    private static final String DEFAULT_ID = "Main Wallet";

    private WalletProfileStore() {}

    public static void ensureDefault(Context context) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        Set<String> ids = readIds(prefs);
        if (ids.isEmpty()) {
            ids.add(DEFAULT_ID);
            prefs.edit()
                    .putString(KEY_ORDERED_IDS, join(ids))
                    .putString(KEY_SELECTED_ID, DEFAULT_ID)
                    .apply();
            return;
        }

        String selected = prefs.getString(KEY_SELECTED_ID, "");
        if (selected == null || selected.isEmpty() || !ids.contains(selected)) {
            prefs.edit().putString(KEY_SELECTED_ID, ids.iterator().next()).apply();
        }
    }

    public static List<String> getWalletIds(Context context) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        ensureDefault(context);
        return new ArrayList<>(readIds(prefs));
    }

    public static String getSelectedWalletId(Context context) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        ensureDefault(context);
        Set<String> ids = readIds(prefs);
        String selected = prefs.getString(KEY_SELECTED_ID, DEFAULT_ID);
        if (selected == null || !ids.contains(selected)) {
            return ids.iterator().next();
        }
        return selected;
    }

    public static String addWallet(Context context, String preferredName) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        ensureDefault(context);

        Set<String> ids = readIds(prefs);
        String base = sanitize(preferredName == null || preferredName.trim().isEmpty() ? "Wallet" : preferredName.trim());
        String candidate = base;
        int index = 2;
        while (ids.contains(candidate)) {
            candidate = base + " " + index;
            index++;
        }
        ids.add(candidate);
        prefs.edit()
                .putString(KEY_ORDERED_IDS, join(ids))
                .putString(KEY_SELECTED_ID, candidate)
                .apply();
        return candidate;
    }

    public static void setSelectedWalletId(Context context, String walletId) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        ensureDefault(context);
        Set<String> ids = readIds(prefs);
        if (!ids.contains(walletId)) {
            return;
        }
        prefs.edit().putString(KEY_SELECTED_ID, walletId).apply();
    }

    public static void removeWallet(Context context, String walletId) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        ensureDefault(context);
        Set<String> ids = readIds(prefs);
        if (!ids.contains(walletId) || ids.size() <= 1) {
            return;
        }

        ids.remove(walletId);
        String next = ids.iterator().next();
        prefs.edit()
                .putString(KEY_ORDERED_IDS, join(ids))
                .putString(KEY_SELECTED_ID, next)
                .apply();
    }

    public static boolean renameWallet(Context context, String oldId, String newName) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        ensureDefault(context);

        String cleanNewName = sanitize(newName);
        if (cleanNewName.isEmpty() || oldId == null) {
            return false;
        }

        Set<String> ids = readIds(prefs);
        if (!ids.contains(oldId)) {
            return false; // Old ID does not exist
        }
        if (ids.contains(cleanNewName) && !oldId.equals(cleanNewName)) {
            return false; // Target name already exists
        }

        if (oldId.equals(cleanNewName)) {
            return true; // No-op rename
        }

        // Rename directory on disk if oldDir exists
        File oldDir = getWalletDir(context, oldId);
        if (oldDir.exists()) {
            File walletsRoot = new File(context.getFilesDir(), "wallet_profiles");
            String safeNewName = sanitize(cleanNewName).replace(' ', '_');
            File newDir = new File(walletsRoot, safeNewName);

            if (newDir.exists()) {
                newDir.delete();
            }

            boolean renamed = oldDir.renameTo(newDir);
            if (!renamed) {
                // Warning, but keep going with prefs
            }
        }

        // Update ordered IDs
        Set<String> newIds = new LinkedHashSet<>();
        for (String id : ids) {
            if (id.equals(oldId)) {
                newIds.add(cleanNewName);
            } else {
                newIds.add(id);
            }
        }

        // Update selected wallet if it was the renamed one
        SharedPreferences.Editor editor = prefs.edit().putString(KEY_ORDERED_IDS, join(newIds));
        String selected = prefs.getString(KEY_SELECTED_ID, "");
        if (oldId.equals(selected)) {
            editor.putString(KEY_SELECTED_ID, cleanNewName);
        }
        editor.apply();

        return true;
    }

    public static File getWalletDir(Context context, String walletId) {
        File walletsRoot = new File(context.getFilesDir(), "wallet_profiles");
        if (!walletsRoot.exists()) {
            walletsRoot.mkdirs();
        }

        String safeName = sanitize(walletId).replace(' ', '_');
        File walletDir = new File(walletsRoot, safeName);
        if (!walletDir.exists()) {
            walletDir.mkdirs();
        }
        return walletDir;
    }

    private static Set<String> readIds(SharedPreferences prefs) {
        String raw = prefs.getString(KEY_ORDERED_IDS, "");
        LinkedHashSet<String> ids = new LinkedHashSet<>();
        if (raw == null || raw.isEmpty()) {
            return ids;
        }

        String[] parts = raw.split("\\n");
        for (String part : parts) {
            String trimmed = part.trim();
            if (!trimmed.isEmpty()) {
                ids.add(trimmed);
            }
        }
        return ids;
    }

    private static String join(Set<String> ids) {
        StringBuilder builder = new StringBuilder();
        for (String id : ids) {
            if (builder.length() > 0) {
                builder.append('\n');
            }
            builder.append(id);
        }
        return builder.toString();
    }

    private static String sanitize(String input) {
        return input.replaceAll("[^A-Za-z0-9 _-]", "").trim();
    }
}
