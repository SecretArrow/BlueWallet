package com.octopus.wallet;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertTrue;

import android.content.SharedPreferences;
import java.util.HashMap;
import java.util.Map;
import java.util.Random;
import java.util.Set;
import org.junit.Test;

/**
 * Pure-JVM tests for backup reminder date math (explicit {@code nowEpochMs}, no Robolectric) plus
 * the quiz helpers and the thin SharedPreferences wiring, which is exercised through an in-memory
 * fake.
 */
public class BackupReminderLogicTest {

  private static final long DAY = BackupReminderLogic.DAY_MS;
  private static final long T0 = 1_700_000_000_000L;

  // ── isDue: initial grace ────────────────────────────────────────────────

  @Test
  public void isDue_untrackedIsNeverDue() {
    assertFalse(BackupReminderLogic.isDue(T0, 0L, 0L));
  }

  @Test
  public void isDue_freshWalletWithinGraceIsNotDue() {
    assertFalse(BackupReminderLogic.isDue(T0, T0, 0L));
    assertFalse(BackupReminderLogic.isDue(T0 + DAY, T0, 0L));
    assertFalse(BackupReminderLogic.isDue(T0 + 2 * DAY, T0, 0L));
    assertFalse(BackupReminderLogic.isDue(T0 + 3 * DAY - 1, T0, 0L));
  }

  @Test
  public void isDue_dueOnceTheInitialGraceElapses() {
    assertTrue(BackupReminderLogic.isDue(T0 + 3 * DAY, T0, 0L));
    assertTrue(BackupReminderLogic.isDue(T0 + 3 * DAY + 1, T0, 0L));
    assertTrue(BackupReminderLogic.isDue(T0 + 100 * DAY, T0, 0L));
  }

  // ── isDue: 30-day cadence ───────────────────────────────────────────────

  @Test
  public void isDue_notDueWithin30DaysAfterVerification() {
    assertFalse(BackupReminderLogic.isDue(T0, 0L, T0));
    assertFalse(BackupReminderLogic.isDue(T0 + 29 * DAY, 0L, T0));
    assertFalse(BackupReminderLogic.isDue(T0 + 30 * DAY - 1, 0L, T0));
  }

  @Test
  public void isDue_dueExactly30DaysAfterVerification() {
    assertTrue(BackupReminderLogic.isDue(T0 + 30 * DAY, 0L, T0));
    assertTrue(BackupReminderLogic.isDue(T0 + 31 * DAY, 0L, T0));
  }

  @Test
  public void isDue_recentVerificationBeatsOldTracking() {
    long created = T0 - 100 * DAY;
    long verified = T0;
    assertFalse(BackupReminderLogic.isDue(T0 + DAY, created, verified));
  }

  @Test
  public void isDue_clockBehindLastVerificationIsNotDue() {
    assertFalse(BackupReminderLogic.isDue(T0 - 5 * DAY, 0L, T0));
  }

  // ── nextDueAt ───────────────────────────────────────────────────────────

  @Test
  public void nextDueAt_usesGraceBeforeFirstVerification() {
    assertEquals(T0 + 3 * DAY, BackupReminderLogic.nextDueAt(T0, 0L));
  }

  @Test
  public void nextDueAt_uses30DaysAfterVerification() {
    assertEquals(T0 + 30 * DAY, BackupReminderLogic.nextDueAt(0L, T0));
  }

  @Test
  public void nextDueAt_zeroWhenUntracked() {
    assertEquals(0L, BackupReminderLogic.nextDueAt(0L, 0L));
  }

  // ── snooze boundaries ───────────────────────────────────────────────────

  @Test
  public void snooze_suppressesForSevenDays() {
    long snoozeUntil = T0 + 7 * DAY;
    assertTrue(BackupReminderLogic.isSnoozed(T0, snoozeUntil));
    assertTrue(BackupReminderLogic.isSnoozed(T0 + 7 * DAY - 1, snoozeUntil));
    assertFalse(BackupReminderLogic.isSnoozed(T0, 0L));
  }

  @Test
  public void snooze_expiresAtTheBoundary() {
    long snoozeUntil = T0 + 7 * DAY;
    assertFalse(BackupReminderLogic.isSnoozed(snoozeUntil, snoozeUntil));
    assertFalse(BackupReminderLogic.isSnoozed(snoozeUntil + 1, snoozeUntil));
  }

  // ── quiz helpers ────────────────────────────────────────────────────────

  @Test
  public void quizSeed_variesAcrossDays() {
    assertNotEquals(
        BackupReminderLogic.quizSeed(T0),
        BackupReminderLogic.quizSeed(T0 + 24L * 60L * 60L * 1000L));
  }

  @Test
  public void quizPositions_deterministicDistinctInRangeAscending() {
    int[] first = BackupReminderLogic.quizPositions(12, new Random(42L), 2);
    int[] second = BackupReminderLogic.quizPositions(12, new Random(42L), 2);
    assertArrayEquals(first, second);
    assertEquals(2, first.length);
    assertNotEquals(first[0], first[1]);
    for (int position : first) {
      assertTrue(position >= 1 && position <= 12);
    }
    assertTrue(first[0] < first[1]);
  }

  @Test
  public void quizPositions_distinctOverManySeeds() {
    for (long seed = 0; seed < 200; seed++) {
      int[] positions = BackupReminderLogic.quizPositions(12, new Random(seed), 2);
      assertEquals("seed " + seed, 2, positions.length);
      assertNotEquals("seed " + seed, positions[0], positions[1]);
    }
  }

  @Test
  public void quizPositions_clampsToWordCountAndGuardsInput() {
    assertArrayEquals(new int[] {1, 2}, BackupReminderLogic.quizPositions(2, new Random(1L), 2));
    assertArrayEquals(new int[] {1}, BackupReminderLogic.quizPositions(1, new Random(1L), 2));
    assertEquals(0, BackupReminderLogic.quizPositions(0, new Random(1L), 2).length);
    assertEquals(0, BackupReminderLogic.quizPositions(12, new Random(1L), 0).length);
  }

  @Test
  public void wordMatches_trimsAndIgnoresCase() {
    assertTrue(BackupReminderLogic.wordMatches("rural", " Rural "));
    assertTrue(BackupReminderLogic.wordMatches("RURAL", "rural"));
    assertFalse(BackupReminderLogic.wordMatches("rural", "urban"));
    assertFalse(BackupReminderLogic.wordMatches("", "x"));
    assertFalse(BackupReminderLogic.wordMatches(null, "x"));
    assertFalse(BackupReminderLogic.wordMatches("x", null));
  }

  // ── thin persistence wiring (in-memory fake SharedPreferences) ──────────

  @Test
  public void ensureTracked_isIdempotent() {
    FakeSharedPreferences prefs = new FakeSharedPreferences();
    BackupReminderLogic.ensureTracked(prefs, T0);
    BackupReminderLogic.ensureTracked(prefs, T0 + 10 * DAY);
    assertEquals(T0, BackupReminderLogic.getFirstTrackedAt(prefs));
  }

  @Test
  public void markVerified_roundTripsAndClearsSnooze() {
    FakeSharedPreferences prefs = new FakeSharedPreferences();
    BackupReminderLogic.ensureTracked(prefs, T0);
    BackupReminderLogic.snooze(prefs, T0);
    assertTrue(BackupReminderLogic.isSnoozed(prefs, T0 + DAY));

    BackupReminderLogic.markVerified(prefs, T0 + DAY);
    assertEquals(T0 + DAY, BackupReminderLogic.getLastVerifiedAt(prefs));
    assertFalse(BackupReminderLogic.isSnoozed(prefs, T0 + DAY));
  }

  @Test
  public void shouldRemind_followsGraceSnoozeAndCadence() {
    FakeSharedPreferences prefs = new FakeSharedPreferences();
    BackupReminderLogic.ensureTracked(prefs, T0);

    // Within the grace window → not due.
    assertFalse(BackupReminderLogic.shouldRemind(prefs, T0 + 2 * DAY));
    // Grace elapsed → due.
    assertTrue(BackupReminderLogic.shouldRemind(prefs, T0 + 3 * DAY));

    // Snooze suppresses …
    BackupReminderLogic.snooze(prefs, T0 + 3 * DAY);
    assertFalse(BackupReminderLogic.shouldRemind(prefs, T0 + 4 * DAY));
    // … until it expires.
    assertTrue(BackupReminderLogic.shouldRemind(prefs, T0 + 3 * DAY + 7 * DAY));

    // Verification resets to the 30-day cadence.
    BackupReminderLogic.markVerified(prefs, T0 + 10 * DAY);
    assertFalse(BackupReminderLogic.shouldRemind(prefs, T0 + 39 * DAY));
    assertTrue(BackupReminderLogic.shouldRemind(prefs, T0 + 40 * DAY));
  }

  /** Minimal in-memory SharedPreferences used only by these tests. */
  private static final class FakeSharedPreferences implements SharedPreferences {
    private final Map<String, Object> values = new HashMap<>();

    @Override
    public Map<String, ?> getAll() {
      return new HashMap<>(values);
    }

    @Override
    public void registerOnSharedPreferenceChangeListener(
        OnSharedPreferenceChangeListener listener) {}

    @Override
    public void unregisterOnSharedPreferenceChangeListener(
        OnSharedPreferenceChangeListener listener) {}

    @Override
    public String getString(String key, String defValue) {
      Object value = values.get(key);
      return value instanceof String ? (String) value : defValue;
    }

    @Override
    public Set<String> getStringSet(String key, Set<String> defValue) {
      throw new UnsupportedOperationException();
    }

    @Override
    public int getInt(String key, int defValue) {
      Object value = values.get(key);
      return value instanceof Integer ? (Integer) value : defValue;
    }

    @Override
    public long getLong(String key, long defValue) {
      Object value = values.get(key);
      return value instanceof Long ? (Long) value : defValue;
    }

    @Override
    public float getFloat(String key, float defValue) {
      Object value = values.get(key);
      return value instanceof Float ? (Float) value : defValue;
    }

    @Override
    public boolean getBoolean(String key, boolean defValue) {
      Object value = values.get(key);
      return value instanceof Boolean ? (Boolean) value : defValue;
    }

    @Override
    public boolean contains(String key) {
      return values.containsKey(key);
    }

    @Override
    public Editor edit() {
      return new Editor() {
        @Override
        public Editor putString(String key, String value) {
          values.put(key, value);
          return this;
        }

        @Override
        public Editor putStringSet(String key, Set<String> value) {
          throw new UnsupportedOperationException();
        }

        @Override
        public Editor putInt(String key, int value) {
          values.put(key, value);
          return this;
        }

        @Override
        public Editor putLong(String key, long value) {
          values.put(key, value);
          return this;
        }

        @Override
        public Editor putFloat(String key, float value) {
          values.put(key, value);
          return this;
        }

        @Override
        public Editor putBoolean(String key, boolean value) {
          values.put(key, value);
          return this;
        }

        @Override
        public Editor remove(String key) {
          values.remove(key);
          return this;
        }

        @Override
        public Editor clear() {
          values.clear();
          return this;
        }

        @Override
        public boolean commit() {
          return true;
        }

        @Override
        public void apply() {
          // In-memory fake — nothing to flush.
        }
      };
    }
  }
}
