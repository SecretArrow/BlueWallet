package com.octopus.wallet;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Base64;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.room.Database;
import androidx.room.Room;
import androidx.room.RoomDatabase;
import androidx.security.crypto.EncryptedSharedPreferences;
import androidx.security.crypto.MasterKey;

import net.sqlcipher.database.SupportFactory;

import java.security.SecureRandom;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Room database for local, offline-capable caching of wallet data.
 *
 * <h3>Current tables</h3>
 * <ul>
 *   <li>{@link TxHistoryEntity tx_history} — cached transaction history per wallet</li>
 *   <li>{@link TokenSnapshotEntity token_snapshot} — cached dashboard balance/token snapshot</li>
 * </ul>
 *
 * <h3>Usage (background thread required)</h3>
 * <pre>{@code
 * TxHistoryDao dao = OctraDatabase.get(context).txHistoryDao();
 *
 * // Persist a page of results
 * List<TxHistoryEntity> entities = ...;
 * dao.insertOrReplaceAll(entities);
 *
 * // Read cached data
 * List<TxHistoryEntity> cached = dao.getByWallet(walletId, 50);
 * }</pre>
 *
 * <h3>Migration strategy</h3>
 * {@link androidx.room.RoomDatabase.Builder#fallbackToDestructiveMigration()} is enabled so that
 * schema version bumps during development are handled automatically by wiping and rebuilding the
 * cache (safe because all data is re-fetchable from the network).
 */
@Database(
    entities = {TxHistoryEntity.class, TokenSnapshotEntity.class},
    version  = 2,
    exportSchema = false
)
public abstract class OctraDatabase extends RoomDatabase {

    private static final String TAG = "OctraDatabase";
    private static final String DB_NAME = "octra_wallet_cache.db";
    private static final String SECURE_PREFS = "octra_db_secure";
    private static final String KEY_DB_PASS = "db_passphrase_b64";
    private static volatile OctraDatabase INSTANCE;
    private static final Object LOCK = new Object();
    private static final ExecutorService dbExecutor = Executors.newSingleThreadExecutor();

    // ── Abstract DAO accessors ─────────────────────────────────────────────

    public abstract TxHistoryDao txHistoryDao();

    public abstract TokenSnapshotDao tokenSnapshotDao();

    // ── Singleton ─────────────────────────────────────────────────────────

    /**
     * Returns the application-scoped singleton instance.
     * Thread-safe via double-checked locking.
     */
    public static OctraDatabase get(@NonNull Context context) {
        if (INSTANCE == null) {
            synchronized (LOCK) {
                if (INSTANCE == null) {
                    try {
                        // Initialize SQLCipher before opening database
                        net.sqlcipher.database.SQLiteDatabase.loadLibs(context.getApplicationContext());
                        
                        byte[] passphrase = getOrCreateDbPassphrase(context.getApplicationContext());
                        SupportFactory factory = new SupportFactory(passphrase);
                        
                        INSTANCE = Room.databaseBuilder(
                                        context.getApplicationContext(),
                                        OctraDatabase.class,
                                        DB_NAME)
                                .openHelperFactory(factory)
                                // Wipe & rebuild when the schema version changes.
                                // All cached data is recoverable from network, so this is safe.
                                .fallbackToDestructiveMigration()
                                .build();
                        
                        Log.i(TAG, "Database initialized successfully");
                    } catch (Exception e) {
                        Log.e(TAG, "Failed to initialize database: " + e.getMessage(), e);
                        // Fallback to non-encrypted database
                        try {
                            INSTANCE = Room.databaseBuilder(
                                            context.getApplicationContext(),
                                            OctraDatabase.class,
                                            DB_NAME)
                                    .fallbackToDestructiveMigration()
                                    .build();
                            Log.w(TAG, "Database initialized without encryption (fallback)");
                        } catch (Exception ex) {
                            Log.e(TAG, "Failed to initialize database even without encryption", ex);
                            throw new RuntimeException("Failed to initialize database", ex);
                        }
                    }
                }
            }
        }
        return INSTANCE;
    }

    private static SharedPreferences securePrefs(Context ctx) {
        try {
            MasterKey key = new MasterKey.Builder(ctx)
                    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                    .build();
            return EncryptedSharedPreferences.create(
                    ctx,
                    SECURE_PREFS,
                    key,
                    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            );
        } catch (Exception e) {
            Log.w(TAG, "EncryptedSharedPreferences not available, using plain preferences", e);
            return ctx.getSharedPreferences(SECURE_PREFS + "_plain", Context.MODE_PRIVATE);
        }
    }

    private static byte[] getOrCreateDbPassphrase(Context ctx) {
        SharedPreferences prefs = securePrefs(ctx);
        String existing = prefs.getString(KEY_DB_PASS, null);
        if (existing != null && !existing.isEmpty()) {
            try {
                return Base64.decode(existing, Base64.NO_WRAP);
            } catch (Exception ignored) {
                // fall through and regenerate
                Log.w(TAG, "Failed to decode existing passphrase, generating new one");
            }
        }

        byte[] raw = new byte[32];
        new SecureRandom().nextBytes(raw);
        String enc = Base64.encodeToString(raw, Base64.NO_WRAP);
        prefs.edit().putString(KEY_DB_PASS, enc).apply();
        return raw;
    }

    /**
     * Closes the database and clears the singleton reference.
     * Should only be called in tests or when the application process is torn down.
     */
    public static synchronized void destroy() {
        if (INSTANCE != null && INSTANCE.isOpen()) {
            INSTANCE.close();
        }
        INSTANCE = null;
    }
    
    /**
     * Executes a database operation on a background thread.
     * This prevents database operations from running on the main thread.
     */
    public static void executeDbOperation(@NonNull Runnable operation) {
        dbExecutor.execute(() -> {
            try {
                operation.run();
            } catch (Exception e) {
                Log.e(TAG, "Database operation failed: " + e.getMessage(), e);
            }
        });
    }
}
