package com.octopus.wallet;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.util.LinkedHashSet;
import java.util.Set;
import org.junit.Before;
import org.junit.Test;

/**
 * Pure-JVM tests for watch-only wallets: flag persistence round-trip, the send decision helper, and
 * the fail-safe send guard. No Robolectric — the suite mirrors the codebase convention
 * (BookmarkStoreTest style) of driving the pure core the same way the Context layer does: raw
 * string in, mutated raw string out.
 */
public class WatchOnlyStoreTest {

  // Simulated SharedPreferences value (what readRaw/write shuttle).
  private String stored = "";

  // Field-real address (AboutActivity donation address, 47 chars).
  private static final String GOOD_ADDRESS = "oct5ZPf49ZYNnA1hopXe9EcDbiBPhgwJyudxLaLhHefEmFt";

  @Before
  public void resetStorage() {
    stored = "";
  }

  // ── Test doubles of the Context-facing methods ────────────────────

  private boolean isWatchOnly(String walletId) {
    return WatchOnlyStore.decode(stored).contains(walletId == null ? "" : walletId.trim());
  }

  private void markWatchOnly(String walletId) {
    Set<String> ids = WatchOnlyStore.decode(stored);
    ids.add(walletId.trim());
    stored = WatchOnlyStore.encode(ids);
  }

  private void unmarkWatchOnly(String walletId) {
    Set<String> ids = WatchOnlyStore.decode(stored);
    if (ids.remove(walletId.trim())) {
      stored = WatchOnlyStore.encode(ids);
    }
  }

  // ── Flag persistence round-trip ───────────────────────────────────

  @Test
  public void markUnmark_roundTripsTheFlag() {
    assertFalse(isWatchOnly("Account 1"));
    markWatchOnly("Account 1");
    assertTrue("flag persisted after mark", isWatchOnly("Account 1"));
    assertFalse("other wallets unaffected", isWatchOnly("Account 2"));

    unmarkWatchOnly("Account 1");
    assertFalse("flag cleared after unmark", isWatchOnly("Account 1"));
    assertEquals("empty set encodes back to the empty raw value", "", stored);
  }

  @Test
  public void encoding_isOrderedDedupedAndBlankSafe() {
    markWatchOnly("Account 2");
    markWatchOnly("Account 1");
    markWatchOnly("Account 2"); // idempotent re-mark

    Set<String> ids = WatchOnlyStore.decode(stored);
    assertEquals(2, ids.size());
    // Import order is preserved (LinkedHashSet semantics).
    assertEquals("Account 2", ids.iterator().next());
    assertTrue(ids.contains("Account 1"));

    // Blank / whitespace entries never survive a round-trip.
    Set<String> dirty = new LinkedHashSet<>();
    dirty.add("  Account 3  ");
    dirty.add("");
    dirty.add(null);
    assertEquals("Account 3", WatchOnlyStore.encode(dirty));
  }

  @Test
  public void decode_isBlankSafeAndTrims() {
    assertTrue(WatchOnlyStore.decode(null).isEmpty());
    assertTrue(WatchOnlyStore.decode("").isEmpty());
    assertTrue(WatchOnlyStore.decode("   ").isEmpty());
    assertEquals(2, WatchOnlyStore.decode(" Account 1 \n\nAccount 2 \n").size());
    // Split on \n only — wallet names may contain spaces.
    assertTrue(WatchOnlyStore.decode("Account 1").contains("Account 1"));
  }

  // ── Send decision + fail-safe guard ───────────────────────────────

  @Test
  public void canSend_returnsFalseForWatchOnlyTrueOtherwise() {
    assertFalse("watch-only can never send", WalletRepository.canSend(true));
    assertTrue("spendable wallets can send", WalletRepository.canSend(false));
  }

  @Test
  public void requireSendable_throwsForWatchOnlyWithBlockMessage() {
    try {
      TxInputValidator.requireSendable(true);
      org.junit.Assert.fail("expected IllegalArgumentException for watch-only wallet");
    } catch (IllegalArgumentException e) {
      assertEquals("Watch-only wallet cannot send funds", e.getMessage());
    }
  }

  @Test
  public void requireSendable_isNoOpForSpendableWallets() {
    TxInputValidator.requireSendable(false); // must not throw
  }

  // ── Address validation (import entry point) ───────────────────────

  @Test
  public void isValidOctAddress_acceptsWellFormedAddresses() {
    assertTrue(TxInputValidator.isValidOctAddress(GOOD_ADDRESS));
    assertTrue(TxInputValidator.isValidOctAddress("  " + GOOD_ADDRESS + "  "));
  }

  @Test
  public void isValidOctAddress_rejectsMalformedInput() {
    assertFalse(TxInputValidator.isValidOctAddress(null));
    assertFalse(TxInputValidator.isValidOctAddress(""));
    assertFalse(TxInputValidator.isValidOctAddress("   "));
    assertFalse(TxInputValidator.isValidOctAddress("oct"));
    assertFalse(TxInputValidator.isValidOctAddress("notanaddress"));
    // Right prefix, wrong length.
    assertFalse(TxInputValidator.isValidOctAddress(GOOD_ADDRESS.substring(0, 46)));
    assertFalse(TxInputValidator.isValidOctAddress(GOOD_ADDRESS + "x"));
    // Right length, wrong prefix.
    assertFalse(TxInputValidator.isValidOctAddress("xct" + GOOD_ADDRESS.substring(3)));
  }
}
