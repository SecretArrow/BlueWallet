package com.octopus.wallet;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONObject;

import java.net.URI;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * Startpage "10 URL terakhir" store (plan.txt § Browser Startpage).
 *
 * <p>Persisted as JSON in SharedPreferences, max {@link #MAX_ENTRIES} entries
 * ordered newest-first. Same-URL revisits upsert (timestamp + title refresh,
 * no duplicates). Only {@code http/https} pages are recorded; internal,
 * blank, error and sensitive URLs are filtered. Callers must skip recording
 * in private mode and call {@link #clearAll} from browsing-data deletion.
 */
public final class RecentVisitsStore {

    public static final int MAX_ENTRIES = 10;

    private static final String PREFS = "recent_visits";
    private static final String KEY_ENTRIES = "entries_v1";

    private RecentVisitsStore() {
    }

    /** One recent visit row. */
    public static final class Entry {
        public final String url;
        public final String title;
        public final String domain;
        public final long visitedAt;

        public Entry(String url, String title, String domain, long visitedAt) {
            this.url = url == null ? "" : url;
            this.title = title == null ? "" : title;
            this.domain = domain == null ? "" : domain;
            this.visitedAt = visitedAt;
        }
    }

    /** Record a successful navigation. No-op when the URL is not recordable. */
    public static synchronized void recordVisit(Context context, String url, String title) {
        if (context == null || !isRecordable(url)) return;
        String normalized = normalizeForDedup(url);
        if (normalized.isEmpty()) return;
        List<Entry> current = getRecent(context);
        Map<String, Entry> byUrl = new LinkedHashMap<>();
        String domain = domainOf(normalized);
        String safeTitle = title == null ? "" : title.trim();
        if (safeTitle.isEmpty()) safeTitle = domain;
        byUrl.put(normalized, new Entry(normalized, safeTitle, domain, System.currentTimeMillis()));
        for (Entry e : current) {
            if (!byUrl.containsKey(e.url) && byUrl.size() < MAX_ENTRIES) {
                byUrl.put(e.url, e);
            }
        }
        save(context, new ArrayList<>(byUrl.values()));
    }

    public static synchronized List<Entry> getRecent(Context context) {
        List<Entry> out = new ArrayList<>();
        if (context == null) return out;
        try {
            String raw = prefs(context).getString(KEY_ENTRIES, "[]");
            JSONArray arr = new JSONArray(raw == null ? "[]" : raw);
            for (int i = 0; i < arr.length() && out.size() < MAX_ENTRIES; i++) {
                JSONObject o = arr.optJSONObject(i);
                if (o == null) continue;
                String url = o.optString("url", "").trim();
                if (url.isEmpty() || !isRecordable(url)) continue;
                out.add(new Entry(url,
                        o.optString("title", ""),
                        o.optString("domain", domainOf(url)),
                        o.optLong("visitedAt", 0L)));
            }
        } catch (Exception ignored) {
            // Corrupt JSON: fail open with an empty list, never crash startpage.
        }
        return out;
    }

    public static synchronized void remove(Context context, String url) {
        if (context == null || url == null) return;
        String normalized = normalizeForDedup(url);
        List<Entry> current = getRecent(context);
        List<Entry> kept = new ArrayList<>();
        for (Entry e : current) {
            if (!e.url.equals(normalized)) kept.add(e);
        }
        save(context, kept);
    }

    public static synchronized void clearAll(Context context) {
        if (context == null) return;
        prefs(context).edit().remove(KEY_ENTRIES).apply();
    }

    // ── Pure helpers (unit-tested, no Android beyond URI) ───────────────────

    /** True only for real http/https website URLs safe to show on Startpage. */
    public static boolean isRecordable(String url) {
        if (url == null) return false;
        String t = url.trim();
        if (t.isEmpty()) return false;
        String low = t.toLowerCase(Locale.US);
        if (low.startsWith("about:") || low.startsWith("chrome://")
                || low.startsWith("chrome-") || low.startsWith("file://")
                || low.startsWith("data:") || low.startsWith("javascript:")
                || low.startsWith("blob:") || low.startsWith("content:")
                || low.startsWith("intent:") || low.startsWith("market:")
                || low.startsWith("tel:") || low.startsWith("mailto:")
                || low.startsWith("sms:") || low.startsWith("octra-wallet:")
                || low.startsWith("octra-local:") || low.startsWith("octra:")
                || low.startsWith("oct://")) {
            return false;
        }
        if (!low.startsWith("http://") && !low.startsWith("https://")) return false;
        // Sensitive query material must never land on Startpage.
        if (low.contains("private_key") || low.contains("privatekey")
                || low.contains("mnemonic") || low.contains("seed_phrase")
                || low.contains("seedphrase") || low.contains("password")
                || low.contains("pin=")) {
            return false;
        }
        try {
            URI uri = new URI(t);
            String host = uri.getHost();
            return host != null && !host.trim().isEmpty();
        } catch (Exception e) {
            return false;
        }
    }

    /** Dedup key: trimmed URL without fragment, root trailing slash removed. */
    public static String normalizeForDedup(String url) {
        if (url == null) return "";
        String t = url.trim();
        if (t.isEmpty()) return "";
        int hash = t.indexOf('#');
        if (hash >= 0) t = t.substring(0, hash);
        t = t.trim();
        // Drop a single trailing slash on bare roots (https://x/ == https://x).
        try {
            URI uri = new URI(t);
            String path = uri.getPath();
            if ("/".equals(path)) {
                t = t.substring(0, t.length() - 1);
            }
        } catch (Exception ignored) {
            // Keep the trimmed string; isRecordable already validated it.
        }
        return t;
    }

    static String domainOf(String url) {
        try {
            URI uri = new URI(url);
            String host = uri.getHost();
            return host == null ? "" : host.toLowerCase(Locale.US);
        } catch (Exception e) {
            return "";
        }
    }

    private static void save(Context context, List<Entry> entries) {
        try {
            JSONArray arr = new JSONArray();
            for (Entry e : entries) {
                if (arr.length() >= MAX_ENTRIES) break;
                JSONObject o = new JSONObject();
                o.put("url", e.url);
                o.put("title", e.title);
                o.put("domain", e.domain);
                o.put("visitedAt", e.visitedAt);
                arr.put(o);
            }
            prefs(context).edit().putString(KEY_ENTRIES, arr.toString()).apply();
        } catch (Exception ignored) {
            // Storage-full / JSON failure: startpage keeps in-memory state.
        }
    }

    private static SharedPreferences prefs(Context context) {
        return context.getApplicationContext()
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }
}
