package com.octopus.wallet;

import android.content.SharedPreferences;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.Random;

/**
 * Backup reminder date math + seed-verification quiz helpers.
 *
 * <p>Mirrors the Flutter {@code BackupReminder} / {@code VerifyBackupLogic} services. All decision
 * methods take an explicit {@code long nowEpochMs} so the logic is unit-testable on the JVM without
 * Robolectric (see {@code BackupReminderLogicTest}).
 *
 * <p>The reminder state is GLOBAL (not per wallet): native wallet ids are human-readable display
 * names that change on rename, so no wallet id is stable across both apps. State lives in the
 * {@value #PREFS_NAME} SharedPreferences file; a stored value of {@code 0} means "not recorded".
 *
 * <p>Semantics (same boundaries as the Flutter side):
 *
 * <ul>
 *   <li>never verified AND tracking started ≥ {@link #INITIAL_GRACE_MS} ago → due;
 *   <li>last verification ≥ {@link #REMIND_EVERY_MS} ago → due;
 *   <li>a snooze suppresses the reminder until its expiry.
 * </ul>
 */
public final class BackupReminderLogic {

  public static final long DAY_MS = 24L * 60L * 60L * 1000L;
  public static final long INITIAL_GRACE_MS = 3L * DAY_MS;
  public static final long REMIND_EVERY_MS = 30L * DAY_MS;
  public static final long SNOOZE_MS = 7L * DAY_MS;

  /** SharedPreferences file used by the thin persistence wiring. */
  public static final String PREFS_NAME = "backup_reminder_prefs";

  private static final String KEY_FIRST_TRACKED_AT = "first_tracked_at";
  private static final String KEY_LAST_VERIFIED_AT = "last_verified_at";
  private static final String KEY_SNOOZE_UNTIL = "snooze_until";

  private BackupReminderLogic() {}

  // ── Pure date math ─────────────────────────────────────────────────────

  /**
   * Whether the reminder is due at {@code nowEpochMs}.
   *
   * <p>Boundary convention: the reminder fires once the full interval has elapsed — a wallet
   * tracked exactly {@link #INITIAL_GRACE_MS} ago is due, and a verification exactly {@link
   * #REMIND_EVERY_MS} ago is due.
   */
  public static boolean isDue(long nowEpochMs, long firstTrackedAtMs, long lastVerifiedAtMs) {
    if (lastVerifiedAtMs > 0) {
      return nowEpochMs - lastVerifiedAtMs >= REMIND_EVERY_MS;
    }
    if (firstTrackedAtMs > 0) {
      return nowEpochMs - firstTrackedAtMs >= INITIAL_GRACE_MS;
    }
    return false;
  }

  /**
   * True while the snooze expiring at {@code snoozeUntilMs} is active. The boundary is exclusive:
   * at exactly {@code snoozeUntilMs} it has expired.
   */
  public static boolean isSnoozed(long nowEpochMs, long snoozeUntilMs) {
    return snoozeUntilMs > nowEpochMs;
  }

  /** Epoch ms when the reminder next becomes due, or 0 when untracked. */
  public static long nextDueAt(long firstTrackedAtMs, long lastVerifiedAtMs) {
    if (lastVerifiedAtMs > 0) {
      return lastVerifiedAtMs + REMIND_EVERY_MS;
    }
    if (firstTrackedAtMs > 0) {
      return firstTrackedAtMs + INITIAL_GRACE_MS;
    }
    return 0L;
  }

  // ── Quiz helpers (seed-phrase verification) ────────────────────────────

  /**
   * Deterministic day-scoped quiz seed: stable within a day, different across days (wallet ids are
   * not stable, so the seed is global).
   */
  public static long quizSeed(long nowEpochMs) {
    Calendar calendar = Calendar.getInstance();
    calendar.setTimeInMillis(nowEpochMs);
    return calendar.get(Calendar.YEAR) * 1000L + calendar.get(Calendar.DAY_OF_YEAR);
  }

  /**
   * {@code count} distinct quiz positions in {@code 1..wordCount}, ascending. Asks for fewer
   * positions when the phrase is shorter than {@code count}; returns an empty array for
   * non-positive word counts.
   */
  public static int[] quizPositions(int wordCount, Random random, int count) {
    if (wordCount <= 0 || count <= 0) {
      return new int[0];
    }
    int wanted = Math.min(count, wordCount);
    List<Integer> picked = new ArrayList<>();
    while (picked.size() < wanted) {
      int candidate = random.nextInt(wordCount) + 1;
      if (!picked.contains(candidate)) {
        picked.add(candidate);
      }
    }
    Collections.sort(picked);
    int[] positions = new int[wanted];
    for (int i = 0; i < wanted; i++) {
      positions[i] = picked.get(i);
    }
    return positions;
  }

  /** Single-word comparison: trimmed and case-insensitive (in memory only). */
  public static boolean wordMatches(String expected, String actual) {
    if (expected == null || actual == null) {
      return false;
    }
    String normalized = expected.trim().toLowerCase(Locale.ROOT);
    return !normalized.isEmpty() && normalized.equals(actual.trim().toLowerCase(Locale.ROOT));
  }

  // ── Thin SharedPreferences wiring ──────────────────────────────────────

  public static long getFirstTrackedAt(SharedPreferences prefs) {
    return prefs.getLong(KEY_FIRST_TRACKED_AT, 0L);
  }

  public static long getLastVerifiedAt(SharedPreferences prefs) {
    return prefs.getLong(KEY_LAST_VERIFIED_AT, 0L);
  }

  public static boolean isSnoozed(SharedPreferences prefs, long nowEpochMs) {
    return isSnoozed(nowEpochMs, prefs.getLong(KEY_SNOOZE_UNTIL, 0L));
  }

  /**
   * Records when backup tracking began (idempotent). Legacy installs adopt the grace window from
   * their first visit to the keys screen.
   */
  public static void ensureTracked(SharedPreferences prefs, long nowEpochMs) {
    if (prefs.getLong(KEY_FIRST_TRACKED_AT, 0L) == 0L) {
      prefs.edit().putLong(KEY_FIRST_TRACKED_AT, nowEpochMs).apply();
    }
  }

  /** Marks the backup verified at {@code nowEpochMs}; clears any snooze. */
  public static void markVerified(SharedPreferences prefs, long nowEpochMs) {
    prefs.edit().putLong(KEY_LAST_VERIFIED_AT, nowEpochMs).remove(KEY_SNOOZE_UNTIL).apply();
  }

  /** Hides the reminder until {@code nowEpochMs + SNOOZE_MS}. */
  public static void snooze(SharedPreferences prefs, long nowEpochMs) {
    prefs.edit().putLong(KEY_SNOOZE_UNTIL, nowEpochMs + SNOOZE_MS).apply();
  }

  /** Composite UI check: due and not snoozed. */
  public static boolean shouldRemind(SharedPreferences prefs, long nowEpochMs) {
    if (isSnoozed(prefs, nowEpochMs)) {
      return false;
    }
    return isDue(nowEpochMs, getFirstTrackedAt(prefs), getLastVerifiedAt(prefs));
  }
}
