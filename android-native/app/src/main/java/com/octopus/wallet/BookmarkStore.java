package com.octopus.wallet;

import android.content.Context;
import android.content.SharedPreferences;
import java.util.ArrayList;
import java.util.List;
import org.json.JSONArray;
import org.json.JSONObject;

/**
 * Persistent browser bookmarks (plan.txt § "Akses cepat ke bookmark", native parity with the
 * Flutter side's SharedPreferences-backed store).
 *
 * <p>Persisted as a JSON array of {@code {"name","url"}} objects in the {@code browser_bookmarks}
 * SharedPreferences file. Parsing is defensive: malformed entries are skipped, malformed JSON never
 * throws. The pure JSON core (parse/serialize/upsert) is package-private and JVM-unit-tested; the
 * Context-facing methods are thin read-modify-write wrappers.
 */
public final class BookmarkStore {

  public static final int MAX_ENTRIES = 20;

  private static final String PREFS = "browser_bookmarks";
  private static final String KEY_ENTRIES = "bookmarks_v1";

  private BookmarkStore() {}

  /** One bookmark row (name is display-only; url is the identity). */
  public static final class Bookmark {
    public final String name;
    public final String url;

    public Bookmark(String name, String url) {
      this.name = name == null ? "" : name.trim();
      this.url = url == null ? "" : url.trim();
    }
  }

  /** All bookmarks in stored order (oldest first). Never returns null, never throws. */
  public static synchronized List<Bookmark> list(Context context) {
    return parse(readRaw(context));
  }

  /**
   * Adds (or re-names) a bookmark. Dedupe by URL — an existing entry keeps its position but gets
   * the new name. When the list grows past {@link #MAX_ENTRIES} the oldest entries are trimmed.
   * Returns true when the store changed.
   */
  public static synchronized boolean add(Context context, String name, String url) {
    if (context == null) {
      return false;
    }
    List<Bookmark> updated = upsert(parse(readRaw(context)), name, url);
    if (updated == null) {
      return false;
    }
    writeRaw(context, serialize(updated));
    return true;
  }

  /** Removes the bookmark with the given URL. Returns true when one was removed. */
  public static synchronized boolean remove(Context context, String url) {
    if (context == null) {
      return false;
    }
    List<Bookmark> current = parse(readRaw(context));
    List<Bookmark> kept = removeUrl(current, url);
    if (kept.size() == current.size()) {
      return false;
    }
    writeRaw(context, serialize(kept));
    return true;
  }

  /** True when a bookmark with the given URL exists. */
  public static boolean contains(Context context, String url) {
    if (context == null) {
      return false;
    }
    return hasUrl(parse(readRaw(context)), url);
  }

  /** Wipes all bookmarks (browsing-data deletion / "Clear all"). */
  public static void clearAll(Context context) {
    if (context == null) {
      return;
    }
    prefs(context).edit().remove(KEY_ENTRIES).apply();
  }

  // ── Pure JSON core (JVM-testable, no Context) ─────────────────────

  /** Parses the persisted JSON array defensively — malformed data yields an empty list. */
  static List<Bookmark> parse(String rawJson) {
    List<Bookmark> out = new ArrayList<>();
    if (rawJson == null || rawJson.trim().isEmpty()) {
      return out;
    }
    try {
      JSONArray arr = new JSONArray(rawJson);
      for (int i = 0; i < arr.length() && out.size() < MAX_ENTRIES; i++) {
        JSONObject o = arr.optJSONObject(i);
        if (o == null) {
          continue; // Malformed entry — skip, never throw.
        }
        String url = o.optString("url", "").trim();
        if (url.isEmpty() || !RecentVisitsStore.isRecordable(url)) {
          continue;
        }
        String name = o.optString("name", "").trim();
        if (name.isEmpty()) {
          name = RecentVisitsStore.domainOf(url);
        }
        out.add(new Bookmark(name, url));
      }
    } catch (Exception ignored) {
      // Corrupt JSON: fail open with an empty list, never crash startpage.
    }
    return out;
  }

  /** Serializes bookmarks back to JSON; never throws. */
  static String serialize(List<Bookmark> entries) {
    try {
      JSONArray arr = new JSONArray();
      if (entries != null) {
        for (Bookmark b : entries) {
          if (b == null || b.url.isEmpty()) {
            continue;
          }
          JSONObject o = new JSONObject();
          o.put("name", b.name);
          o.put("url", b.url);
          arr.put(o);
        }
      }
      return arr.toString();
    } catch (Exception ignored) {
      return "[]";
    }
  }

  /**
   * Upsert policy: only recordable http/https URLs are accepted, same-URL entries are re-named in
   * place, new entries append at the end and the oldest entries are trimmed beyond {@link
   * #MAX_ENTRIES}. Returns null when nothing changed or the input was rejected.
   */
  static List<Bookmark> upsert(List<Bookmark> current, String name, String url) {
    String cleanUrl = url == null ? "" : url.trim();
    if (!RecentVisitsStore.isRecordable(cleanUrl)) {
      return null;
    }
    List<Bookmark> out = new ArrayList<>(current == null ? new ArrayList<>() : current);
    String cleanName = name == null ? "" : name.trim();
    if (cleanName.isEmpty()) {
      cleanName = RecentVisitsStore.domainOf(cleanUrl);
    }
    if (cleanName.isEmpty()) {
      cleanName = cleanUrl;
    }
    for (int i = 0; i < out.size(); i++) {
      if (out.get(i).url.equals(cleanUrl)) {
        if (out.get(i).name.equals(cleanName)) {
          return null; // Identical entry — no change.
        }
        out.set(i, new Bookmark(cleanName, cleanUrl));
        return out;
      }
    }
    out.add(new Bookmark(cleanName, cleanUrl));
    while (out.size() > MAX_ENTRIES) {
      out.remove(0); // Trim the oldest.
    }
    return out;
  }

  /**
   * Returns a new list without the entry matching {@code url} (same size = nothing was removed).
   */
  static List<Bookmark> removeUrl(List<Bookmark> current, String url) {
    List<Bookmark> out = new ArrayList<>();
    String cleanUrl = url == null ? "" : url.trim();
    if (current != null) {
      for (Bookmark b : current) {
        if (b == null || !b.url.equals(cleanUrl)) {
          out.add(b);
        }
      }
    }
    return out;
  }

  static boolean hasUrl(List<Bookmark> entries, String url) {
    String cleanUrl = url == null ? "" : url.trim();
    if (entries == null) {
      return false;
    }
    for (Bookmark b : entries) {
      if (b != null && b.url.equals(cleanUrl)) {
        return true;
      }
    }
    return false;
  }

  // ── Storage plumbing ──────────────────────────────────────────────

  private static String readRaw(Context context) {
    if (context == null) {
      return "[]";
    }
    try {
      String raw = prefs(context).getString(KEY_ENTRIES, "[]");
      return raw == null ? "[]" : raw;
    } catch (Exception e) {
      return "[]";
    }
  }

  private static void writeRaw(Context context, String json) {
    try {
      prefs(context).edit().putString(KEY_ENTRIES, json).apply();
    } catch (Exception ignored) {
      // Storage-full: keep in-memory state, never crash the browser.
    }
  }

  private static SharedPreferences prefs(Context context) {
    return context.getApplicationContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
  }
}
