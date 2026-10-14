package com.octopus.wallet;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Log;
import androidx.work.ExistingPeriodicWorkPolicy;
import androidx.work.PeriodicWorkRequest;
import androidx.work.WorkManager;
import java.util.concurrent.TimeUnit;

/**
 * Schedules the {@link AutoScanWorker} backstop that keeps checking for incoming transactions while
 * the app is closed.
 *
 * <p>The foreground {@link AutoScanService} only runs while the app process is alive (and shows a
 * persistent notification). This WorkManager request instead survives the app being swiped away and
 * the phone being rebooted: WorkManager persists its queue in its own database and re-registers
 * with JobScheduler on its own — that is why no RECEIVE_BOOT_COMPLETED (or any other new
 * permission) is needed here.
 *
 * <p>The enabled flag is persisted in the {@code background_scan_prefs} SharedPreferences file
 * (mirroring how {@link PollingSettingsStore} and {@code AutoScanActivity} own their prefs files),
 * so the schedule survives app restarts and can be re-armed from {@link
 * OctraWalletApplication#onCreate()}.
 */
public final class BackgroundScanScheduler {

  private static final String LOG_TAG = "BackgroundScanSched"; // ≤23 chars, Log limit

  /** Own prefs file — never merged into another store's file. */
  static final String PREFS = "background_scan_prefs";

  /** Key of the boolean enabled flag inside {@link #PREFS}. */
  static final String KEY_ENABLED = "enabled";

  /**
   * Unique name for the periodic request; shared with {@link AutoScanWorker#TAG_PERIODIC} so both
   * writer and reader agree.
   */
  static final String UNIQUE_WORK_NAME = AutoScanWorker.TAG_PERIODIC;

  /**
   * Periodic interval in minutes.
   *
   * <p>IMPORTANT: 15 minutes is Android's hard platform minimum for periodic work — JobScheduler
   * (which backs WorkManager) never runs a periodic job more often than every 15 minutes, and
   * WorkManager silently clamps shorter intervals up to this floor. A 1-minute cadence is therefore
   * impossible here; sub-15-minute checking is what the in-app {@link AutoScanService} (and Flutter
   * polling) covers while the app is alive. Do not lower this value expecting faster checks.
   */
  static final long INTERVAL_MINUTES = 15L;

  private BackgroundScanScheduler() {}

  /**
   * Returns whether the background backstop is enabled. Defaults to {@code false} on a fresh
   * install.
   */
  public static boolean isEnabled(Context context) {
    return readEnabled(getPrefs(context));
  }

  /**
   * Enables the 15-minute periodic backstop. Idempotent: re-enabling keeps the existing schedule
   * (UPDATE only refreshes the spec, which is constant) rather than resetting the running 15-minute
   * cycle.
   */
  public static void enable(Context context) {
    writeEnabled(getPrefs(context), true);
    enqueue(context, ExistingPeriodicWorkPolicy.UPDATE);
  }

  /**
   * Disables the backstop and cancels any queued periodic work. Idempotent: cancelling unknown work
   * is a no-op.
   */
  public static void disable(Context context) {
    writeEnabled(getPrefs(context), false);
    try {
      WorkManager.getInstance(context).cancelUniqueWork(UNIQUE_WORK_NAME);
    } catch (IllegalStateException e) {
      // WorkManager not initialized (should not happen with the
      // default initializer) — the flag is already cleared, so a
      // later enable() will enqueue a fresh request anyway.
      Log.w(LOG_TAG, "Cannot cancel periodic scan work: " + e.getMessage());
    }
  }

  /**
   * Re-arms the periodic work if (and only if) the user enabled it.
   *
   * <p>Called from {@link OctraWalletApplication#onCreate()} at every process start. Uses the KEEP
   * policy: if WorkManager already holds the request, nothing changes and the running 15-minute
   * cycle is NOT reset (UPDATE on every launch would let frequent app opens starve the check
   * forever); if the request is missing (e.g. an aggressive OEM battery manager wiped WorkManager's
   * database), it is re-created because the persisted flag still says enabled.
   */
  public static void rescheduleIfEnabled(Context context) {
    if (!isEnabled(context)) {
      return;
    }
    enqueue(context, ExistingPeriodicWorkPolicy.KEEP);
  }

  // ── WorkManager plumbing ────────────────────────────────────────────────

  private static void enqueue(Context context, ExistingPeriodicWorkPolicy policy) {
    PeriodicWorkRequest request =
        new PeriodicWorkRequest.Builder(AutoScanWorker.class, INTERVAL_MINUTES, TimeUnit.MINUTES)
            .build();
    try {
      WorkManager.getInstance(context).enqueueUniquePeriodicWork(UNIQUE_WORK_NAME, policy, request);
    } catch (IllegalStateException e) {
      // Flag already persisted; the next app start retries via
      // rescheduleIfEnabled().
      Log.w(LOG_TAG, "Cannot schedule periodic scan work: " + e.getMessage());
    }
  }

  // ── Flag persistence (pure, unit-tested) ────────────────────────────────

  private static SharedPreferences getPrefs(Context context) {
    return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
  }

  /** Reads the enabled flag from any {@link SharedPreferences}. */
  static boolean readEnabled(SharedPreferences prefs) {
    return prefs.getBoolean(KEY_ENABLED, false);
  }

  /** Writes the enabled flag to any {@link SharedPreferences}. */
  static void writeEnabled(SharedPreferences prefs, boolean enabled) {
    prefs.edit().putBoolean(KEY_ENABLED, enabled).apply();
  }
}
