package com.octopus.wallet;

import android.app.Application;
import android.util.Log;
import java.io.File;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class OctraWalletApplication extends Application {

  private static volatile OctraWalletApplication sInstance;

  public static OctraWalletApplication getInstance() {
    return sInstance;
  }

  private static final String TAG = "OctraWalletApp";
  private volatile WalletRepository repository;

  /**
   * Shared, process-scoped I/O executor used by every Activity and Service instead of spawning bare
   * {@code new Thread()} calls. Uses a cached pool so idle threads are reclaimed automatically.
   */
  private final ExecutorService ioExecutor = Executors.newCachedThreadPool();

  @Override
  public void onCreate() {
    super.onCreate();
    sInstance = this;

    try {
      // Initialize SQLCipher native libraries early
      net.sqlcipher.database.SQLiteDatabase.loadLibs(this);
      Log.i(TAG, "SQLCipher native libraries loaded successfully");
    } catch (Exception e) {
      Log.e(TAG, "Failed to load SQLCipher native libraries: " + e.getMessage(), e);
      // Continue anyway - Room will handle fallback
    }

    WalletProfileStore.ensureDefault(this);
    String selectedWalletId = WalletProfileStore.getSelectedWalletId(this);
    // A watch-only wallet holds no native encrypted wallet — booting with
    // one selected would trap the app in the setup flow. Fall back to the
    // first spendable wallet when a watch-only id is somehow selected.
    if (WatchOnlyStore.isWatchOnly(this, selectedWalletId)) {
      for (String id : WalletProfileStore.getWalletIds(this)) {
        if (!WatchOnlyStore.isWatchOnly(this, id)) {
          WalletProfileStore.setSelectedWalletId(this, id);
          selectedWalletId = id;
          break;
        }
      }
    }
    File dataDir = WalletProfileStore.getWalletDir(this, selectedWalletId);

    try {
      OctraNative.getInstance().init(dataDir.getAbsolutePath());
      Log.i(TAG, "OctraNative initialized with data dir: " + dataDir.getAbsolutePath());
    } catch (UnsatisfiedLinkError e) {
      Log.e(TAG, "Failed to load native library octra_wallet_native: " + e.getMessage(), e);
    } catch (Exception e) {
      Log.e(TAG, "Failed to initialize OctraNative: " + e.getMessage(), e);
    }

    if (TxTaskStore.hasRecoverableTasks(this)) {
      TxForegroundService.startRecovery(this);
    }

    // Re-arm the periodic background scan backstop (AutoScanWorker via
    // WorkManager) if the user enabled it. WorkManager persists its own
    // queue across reboots and app kills without any permission — this
    // call only re-creates the unique request if it went missing, and
    // never resets the running 15-minute cycle (KEEP policy).
    try {
      BackgroundScanScheduler.rescheduleIfEnabled(this);
    } catch (Exception e) {
      Log.w(TAG, "Background scan reschedule failed: " + e.getMessage());
    }

    Log.i(TAG, "OctraWalletApplication initialized");
  }

  /**
   * Returns the process-wide {@link WalletRepository} singleton. Uses the Application context, so
   * it is safe to hold across Activity / Service lifecycles.
   */
  public WalletRepository getRepository() {
    if (repository == null) {
      synchronized (this) {
        if (repository == null) {
          repository = new WalletRepository(this);
        }
      }
    }
    return repository;
  }

  /**
   * Returns the shared {@link ExecutorService} for all background I/O work. All activities and
   * services should use this instead of {@code new Thread()}.
   */
  public ExecutorService getIoExecutor() {
    return ioExecutor;
  }
}
