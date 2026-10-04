package com.octopus.wallet;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

/**
 * SharedPreferences-backed store for the user-defined address book.
 * Each entry has a human-readable label and an Octra wallet address.
 */
public final class AddressBookStore {

    private static final String PREFS_NAME = "address_book";
    private static final String KEY_ENTRIES  = "entries";

    private AddressBookStore() {}

    // ── Public model ───────────────────────────────────────────────────────

    public static final class Entry {
        public final String id;
        public final String label;
        public final String address;

        public Entry(String id, String label, String address) {
            this.id      = id      == null ? "" : id.trim();
            this.label   = label   == null ? "" : label.trim();
            this.address = address == null ? "" : address.trim();
        }

        JSONObject toJson() {
            try {
                JSONObject obj = new JSONObject();
                obj.put("id", id);
                obj.put("label", label);
                obj.put("address", address);
                return obj;
            } catch (Exception e) {
                return new JSONObject();
            }
        }

        static Entry fromJson(JSONObject obj) {
            if (obj == null) return null;
            return new Entry(
                    obj.optString("id", ""),
                    obj.optString("label", ""),
                    obj.optString("address", "")
            );
        }
    }

    // ── CRUD operations ────────────────────────────────────────────────────

    /** Returns all saved entries, ordered by time of insertion (newest first). */
    public static List<Entry> getEntries(Context context) {
        List<Entry> result = new ArrayList<>();
        try {
            String raw = prefs(context).getString(KEY_ENTRIES, "[]");
            JSONArray arr = new JSONArray(raw);
            for (int i = 0; i < arr.length(); i++) {
                Entry e = Entry.fromJson(arr.optJSONObject(i));
                if (e != null && !e.address.isEmpty()) {
                    result.add(e);
                }
            }
        } catch (Exception ignored) {}
        return result;
    }

    /**
     * Adds a new entry. The ID is set to the current epoch millis as a string.
     * Returns the created entry along with its generated ID.
     */
    public static Entry addEntry(Context context, String label, String address) {
        String id = String.valueOf(System.currentTimeMillis());
        Entry entry = new Entry(id, label, address);
        List<Entry> existing = getEntries(context);
        // Avoid exact duplicate addresses
        for (Entry e : existing) {
            if (e.address.equalsIgnoreCase(address.trim())) {
                return e; // return the existing entry without duplicating
            }
        }
        existing.add(0, entry); // prepend so newest is first
        persist(context, existing);
        return entry;
    }

    /** Updates the label of an entry identified by ID. */
    public static void updateLabel(Context context, String id, String newLabel) {
        List<Entry> entries = getEntries(context);
        List<Entry> updated = new ArrayList<>();
        for (Entry e : entries) {
            if (e.id.equals(id)) {
                updated.add(new Entry(e.id, newLabel, e.address));
            } else {
                updated.add(e);
            }
        }
        persist(context, updated);
    }

    /** Removes the entry with the given ID. */
    public static void deleteEntry(Context context, String id) {
        List<Entry> entries = getEntries(context);
        List<Entry> filtered = new ArrayList<>();
        for (Entry e : entries) {
            if (!e.id.equals(id)) {
                filtered.add(e);
            }
        }
        persist(context, filtered);
    }

    /** Returns the first entry matching the given address (case-insensitive), or null. */
    public static Entry findByAddress(Context context, String address) {
        if (address == null || address.trim().isEmpty()) return null;
        for (Entry e : getEntries(context)) {
            if (e.address.equalsIgnoreCase(address.trim())) {
                return e;
            }
        }
        return null;
    }

    // ── Internal helpers ───────────────────────────────────────────────────

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
    }

    private static void persist(Context context, List<Entry> entries) {
        JSONArray arr = new JSONArray();
        for (Entry e : entries) {
            arr.put(e.toJson());
        }
        prefs(context).edit().putString(KEY_ENTRIES, arr.toString()).apply();
    }
}
