package com.octopus.wallet;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.util.List;
import org.junit.Before;
import org.junit.Test;

/**
 * Pure-JVM tests for the bookmark store policy (add/list/dedupe/remove/ contains/trim/robust JSON).
 * No Robolectric here — the suite mirrors the codebase convention of driving the pure core the same
 * way the Context layer does: raw JSON string in, mutated raw JSON string out.
 */
public class BookmarkStoreTest {

  // Simulated SharedPreferences value (what readRaw/writeRaw shuttle).
  private String stored = "[]";

  @Before
  public void resetStorage() {
    stored = "[]";
  }

  // ── Test doubles of the Context-facing methods ────────────────────

  private List<BookmarkStore.Bookmark> list() {
    return BookmarkStore.parse(stored);
  }

  private boolean add(String name, String url) {
    List<BookmarkStore.Bookmark> updated = BookmarkStore.upsert(list(), name, url);
    if (updated == null) {
      return false;
    }
    stored = BookmarkStore.serialize(updated);
    return true;
  }

  private boolean remove(String url) {
    List<BookmarkStore.Bookmark> current = list();
    List<BookmarkStore.Bookmark> kept = BookmarkStore.removeUrl(current, url);
    if (kept.size() == current.size()) {
      return false;
    }
    stored = BookmarkStore.serialize(kept);
    return true;
  }

  private boolean contains(String url) {
    return BookmarkStore.hasUrl(list(), url);
  }

  // ── Tests ─────────────────────────────────────────────────────────

  @Test
  public void addThenList_roundTripsNameAndUrl() {
    assertTrue(add("Devnet Explorer", "https://devnet.octrascan.io"));
    List<BookmarkStore.Bookmark> out = list();
    assertEquals(1, out.size());
    assertEquals("Devnet Explorer", out.get(0).name);
    assertEquals("https://devnet.octrascan.io", out.get(0).url);
  }

  @Test
  public void add_dedupesByUrlAndRenamesInPlace() {
    add("Old name", "https://octrascan.io");
    assertTrue(add("New name", "https://octrascan.io"));
    List<BookmarkStore.Bookmark> out = list();
    assertEquals(1, out.size());
    assertEquals("New name", out.get(0).name);
    // A truly identical upsert reports "no change".
    assertNull(BookmarkStore.upsert(out, "New name", "https://octrascan.io"));
  }

  @Test
  public void add_rejectsNonWebUrls() {
    assertFalse(add("internal", "oct://circle123/index.html"));
    assertFalse(add("about", "about:blank"));
    assertFalse(add("blank", "  "));
    assertTrue(list().isEmpty());
  }

  @Test
  public void add_defaultsNameToHostWhenEmpty() {
    add("", "https://devnet.octrascan.io/tx/1");
    List<BookmarkStore.Bookmark> out = list();
    assertEquals("devnet.octrascan.io", out.get(0).name);
  }

  @Test
  public void add_trimsOldestBeyondTwenty() {
    for (int i = 1; i <= 21; i++) {
      assertTrue(add("site" + i, "https://example" + i + ".com/"));
    }
    List<BookmarkStore.Bookmark> out = list();
    assertEquals(BookmarkStore.MAX_ENTRIES, out.size());
    assertEquals("https://example2.com/", out.get(0).url); // oldest trimmed
    assertEquals("https://example21.com/", out.get(out.size() - 1).url);
  }

  @Test
  public void remove_deletesByUrl() {
    add("A", "https://a.io");
    add("B", "https://b.io");
    assertTrue(remove("https://a.io"));
    assertFalse(contains("https://a.io"));
    assertTrue(contains("https://b.io"));
    assertFalse(remove("https://a.io")); // second remove: nothing left
  }

  @Test
  public void contains_matchesOnlyExactUrl() {
    add("A", "https://a.io/page");
    assertTrue(contains("https://a.io/page"));
    assertFalse(contains("https://a.io"));
    assertFalse(contains(null));
    assertFalse(contains(""));
  }

  @Test
  public void clearAll_restartsFromEmpty() {
    add("A", "https://a.io");
    add("B", "https://b.io");
    stored = "[]"; // clearAll removes the key; reads fall back to "[]".
    assertTrue(list().isEmpty());
    assertFalse(contains("https://a.io"));
  }

  @Test
  public void parse_neverThrowsOnMalformedJson() {
    for (String bad :
        new String[] {
          null,
          "",
          "   ",
          "not json",
          "{",
          "[",
          "\"str\"",
          "[\"not-an-object\"]",
          "[{}]",
          "[{\"name\":\"x\"}]"
        }) {
      assertTrue("must not throw for: " + bad, BookmarkStore.parse(bad).isEmpty());
    }
  }

  @Test
  public void parse_skipsUnrecordableEntriesButKeepsValidOnes() {
    stored =
        "[{\"name\":\"good\",\"url\":\"https://good.io\"},"
            + "{\"name\":\"bad\",\"url\":\"oct://circle123\"},"
            + "{\"name\":\"sensitive\",\"url\":\"https://x.io/?mnemonic=word word\"},"
            + "3.5,{\"url\":\"https://unnamed.io\"}]";
    List<BookmarkStore.Bookmark> out = list();
    assertEquals(2, out.size());
    assertEquals("good", out.get(0).name);
    assertEquals("unnamed.io", out.get(1).name); // missing name → host fallback
  }

  @Test
  public void serialize_ignoresInvalidEntriesAndNeverThrows() {
    List<BookmarkStore.Bookmark> mixed = new java.util.ArrayList<>();
    mixed.add(new BookmarkStore.Bookmark("A", "https://a.io"));
    mixed.add(new BookmarkStore.Bookmark(null, null));
    mixed.add(null);
    String json = BookmarkStore.serialize(mixed);
    List<BookmarkStore.Bookmark> back = BookmarkStore.parse(json);
    assertEquals(1, back.size());
    assertEquals("https://a.io", back.get(0).url);
  }

  @Test
  public void bookmark_valueClassIsTrimmedAndNullProof() {
    BookmarkStore.Bookmark b = new BookmarkStore.Bookmark("  L  ", " https://l.io ");
    assertEquals("L", b.name);
    assertEquals("https://l.io", b.url);
    BookmarkStore.Bookmark n = new BookmarkStore.Bookmark(null, null);
    assertEquals("", n.name);
    assertEquals("", n.url);
  }
}
