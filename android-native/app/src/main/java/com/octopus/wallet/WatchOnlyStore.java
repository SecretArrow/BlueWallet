package com.octopus.wallet;

import android.content.Context;
import android.content.SharedPreferences;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/**
 * Tracks wallets imported as address-only (watch-only).
 *
 * <p>A watch-only wallet has NO native encrypted wallet — there is no {@code wallet.oct}, no
 * spendable key, and no PIN requirement. It is identified by its stored address (see {@link
 * WalletAddressStore}) and tracked purely via RPC. Every signing path must reject watch-only
 * wallets (see {@code TxInputValidator.requireSendable} and {@code WalletRepository.canSend}).
 *
 * <p>Storage mirrors the {@link WalletProfileStore} conventions: a single SharedPreferences file
 * holding newline-joined ids. The pure {@link #decode(String)} / {@link #encode(Set)} pair is
 * framework-free so the persistence round-trip is unit-testable without Robolectric.
 */
public final class WatchOnlyStore {

  private static final String PREFS = "watch_only_store";
  private static final String KEY_IDS = "watch_only_ids";

  private WatchOnlyStore() {}

  // ── Pure core (unit-tested) ───────────────────────────────────────────

  /**
   * Parses a persisted raw value into an ordered id set. Blank-safe: null, empty or whitespace-only
   * input yields an empty set.
   */
  public static Set<String> decode(String raw) {
    Set<String> ids = new LinkedHashSet<>();
    if (raw == null || raw.isEmpty()) {
      return ids;
    }
    for (String part : raw.split("\n")) {
      String trimmed = part.trim();
      if (!trimmed.isEmpty()) {
        ids.add(trimmed);
      }
    }
    return ids;
  }

  /** Joins an id set back into the persisted raw value (ordered, deduped). */
  public static String encode(Set<String> ids) {
    if (ids == null || ids.isEmpty()) {
      return "";
    }
    StringBuilder builder = new StringBuilder();
    for (String id : ids) {
      if (id == null || id.trim().isEmpty()) {
        continue;
      }
      if (builder.length() > 0) {
        builder.append('\n');
      }
      builder.append(id.trim());
    }
    return builder.toString();
  }

  // ── Context-facing API (mirrors WalletProfileStore style) ─────────────

  /** Returns true when {@code walletId} was imported as watch-only. */
  public static boolean isWatchOnly(Context context, String walletId) {
    if (context == null || walletId == null || walletId.trim().isEmpty()) {
      return false;
    }
    return decode(readRaw(context)).contains(walletId.trim());
  }

  /**
   * Marks {@code walletId} as watch-only (idempotent).
   *
   * @throws IllegalArgumentException when the id is blank
   */
  public static void markWatchOnly(Context context, String walletId) {
    if (context == null) {
      throw new IllegalArgumentException("Context must not be null");
    }
    if (walletId == null || walletId.trim().isEmpty()) {
      throw new IllegalArgumentException("walletId must not be blank");
    }
    SharedPreferences prefs = prefs(context);
    Set<String> ids = decode(prefs.getString(KEY_IDS, ""));
    ids.add(walletId.trim());
    prefs.edit().putString(KEY_IDS, encode(ids)).apply();
  }

  /** Removes the watch-only flag (wallet deleted or upgraded). Idempotent. */
  public static void unmarkWatchOnly(Context context, String walletId) {
    if (context == null || walletId == null || walletId.trim().isEmpty()) {
      return;
    }
    SharedPreferences prefs = prefs(context);
    Set<String> ids = decode(prefs.getString(KEY_IDS, ""));
    if (ids.remove(walletId.trim())) {
      prefs.edit().putString(KEY_IDS, encode(ids)).apply();
    }
  }

  /** Returns all watch-only wallet ids in import order. */
  public static List<String> getWatchOnlyIds(Context context) {
    if (context == null) {
      return new ArrayList<>();
    }
    return new ArrayList<>(decode(readRaw(context)));
  }

  private static SharedPreferences prefs(Context context) {
    return context.getApplicationContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
  }

  private static String readRaw(Context context) {
    return prefs(context).getString(KEY_IDS, "");
  }
}
