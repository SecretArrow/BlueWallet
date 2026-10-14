package com.octopus.wallet;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.content.SharedPreferences;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import org.junit.Test;

/**
 * Pure-JVM tests for the background-scan enabled flag.
 *
 * <p>This project's unit tests run on the plain JVM (no Robolectric, no {@code
 * androidx.work:work-testing} artifact), so the WorkManager enqueue/cancel plumbing of {@link
 * BackgroundScanScheduler} cannot be exercised here — that needs a framework Context. Only the
 * SharedPreferences flag logic, the part that must survive process restarts, is covered, using an
 * in-memory fake SharedPreferences.
 */
public class BackgroundScanSchedulerTest {

  @Test
  public void readEnabled_defaultsToDisabled() {
    assertFalse(BackgroundScanScheduler.readEnabled(new FakePrefs()));
  }

  @Test
  public void enabledFlag_roundTrips() {
    FakePrefs prefs = new FakePrefs();
    BackgroundScanScheduler.writeEnabled(prefs, true);
    assertTrue(BackgroundScanScheduler.readEnabled(prefs));
    BackgroundScanScheduler.writeEnabled(prefs, false);
    assertFalse(BackgroundScanScheduler.readEnabled(prefs));
    // Re-enable after disable still works (user toggles back on).
    BackgroundScanScheduler.writeEnabled(prefs, true);
    assertTrue(BackgroundScanScheduler.readEnabled(prefs));
  }

  @Test
  public void enableDisable_areIdempotent() {
    FakePrefs prefs = new FakePrefs();
    BackgroundScanScheduler.writeEnabled(prefs, true);
    BackgroundScanScheduler.writeEnabled(prefs, true);
    assertTrue(BackgroundScanScheduler.readEnabled(prefs));
    BackgroundScanScheduler.writeEnabled(prefs, false);
    BackgroundScanScheduler.writeEnabled(prefs, false);
    assertFalse(BackgroundScanScheduler.readEnabled(prefs));
  }

  @Test
  public void constants_matchWorkerContract() {
    assertEquals(AutoScanWorker.TAG_PERIODIC, BackgroundScanScheduler.UNIQUE_WORK_NAME);
    assertEquals("auto_scan_periodic", BackgroundScanScheduler.UNIQUE_WORK_NAME);
    // 15 minutes is Android's hard floor for periodic WorkManager jobs:
    // shorter intervals are silently clamped up, so this must never
    // regress below 15.
    assertEquals(15L, BackgroundScanScheduler.INTERVAL_MINUTES);
    assertEquals("background_scan_prefs", BackgroundScanScheduler.PREFS);
    assertEquals("enabled", BackgroundScanScheduler.KEY_ENABLED);
  }

  /** Minimal in-memory SharedPreferences fake (staged Editor semantics). */
  private static final class FakePrefs implements SharedPreferences {
    private final Map<String, Object> values = new HashMap<>();

    @Override
    public Map<String, ?> getAll() {
      return new HashMap<>(values);
    }

    @Override
    public String getString(String key, String defValue) {
      Object v = values.get(key);
      return v instanceof String ? (String) v : defValue;
    }

    @Override
    public Set<String> getStringSet(String key, Set<String> defValue) {
      Object v = values.get(key);
      @SuppressWarnings("unchecked")
      Set<String> out = v instanceof Set ? (Set<String>) v : null;
      return out != null ? out : defValue;
    }

    @Override
    public int getInt(String key, int defValue) {
      Object v = values.get(key);
      return v instanceof Integer ? (Integer) v : defValue;
    }

    @Override
    public long getLong(String key, long defValue) {
      Object v = values.get(key);
      return v instanceof Long ? (Long) v : defValue;
    }

    @Override
    public float getFloat(String key, float defValue) {
      Object v = values.get(key);
      return v instanceof Float ? (Float) v : defValue;
    }

    @Override
    public boolean getBoolean(String key, boolean defValue) {
      Object v = values.get(key);
      return v instanceof Boolean ? (Boolean) v : defValue;
    }

    @Override
    public boolean contains(String key) {
      return values.containsKey(key);
    }

    // Abstract in older platform jars, default no-ops since API 30:
    // overriding keeps this fake compilable against both shapes.
    @Override
    public void registerOnSharedPreferenceChangeListener(
        OnSharedPreferenceChangeListener listener) {}

    @Override
    public void unregisterOnSharedPreferenceChangeListener(
        OnSharedPreferenceChangeListener listener) {}

    @Override
    public Editor edit() {
      return new FakeEditor(values);
    }

    private static final class FakeEditor implements Editor {
      private final Map<String, Object> target;
      private final Map<String, Object> staged = new HashMap<>();
      private final Set<String> removals = new HashSet<>();
      private boolean clearAll = false;

      FakeEditor(Map<String, Object> target) {
        this.target = target;
      }

      @Override
      public Editor putString(String key, String value) {
        staged.put(key, value);
        removals.remove(key);
        return this;
      }

      @Override
      public Editor putStringSet(String key, Set<String> set) {
        staged.put(key, set);
        removals.remove(key);
        return this;
      }

      @Override
      public Editor putInt(String key, int value) {
        staged.put(key, value);
        removals.remove(key);
        return this;
      }

      @Override
      public Editor putLong(String key, long value) {
        staged.put(key, value);
        removals.remove(key);
        return this;
      }

      @Override
      public Editor putFloat(String key, float value) {
        staged.put(key, value);
        removals.remove(key);
        return this;
      }

      @Override
      public Editor putBoolean(String key, boolean value) {
        staged.put(key, value);
        removals.remove(key);
        return this;
      }

      @Override
      public Editor remove(String key) {
        staged.remove(key);
        removals.add(key);
        return this;
      }

      @Override
      public Editor clear() {
        clearAll = true;
        staged.clear();
        removals.clear();
        return this;
      }

      @Override
      public boolean commit() {
        applyInternal();
        return true;
      }

      @Override
      public void apply() {
        applyInternal();
      }

      private void applyInternal() {
        if (clearAll) {
          target.clear();
        }
        target.keySet().removeAll(removals);
        target.putAll(staged);
      }
    }
  }
}
