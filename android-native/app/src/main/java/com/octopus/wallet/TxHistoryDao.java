package com.octopus.wallet;

import androidx.room.Dao;
import androidx.room.Insert;
import androidx.room.OnConflictStrategy;
import androidx.room.Query;

import java.util.List;

/**
 * Room DAO for cached transaction history.
 *
 * <p>All queries are synchronous and must be called from a background thread
 * (e.g. via {@link java.util.concurrent.ExecutorService} or WorkManager).</p>
 */
@Dao
public interface TxHistoryDao {

    // ── Write ──────────────────────────────────────────────────────────────

    /**
     * Inserts or replaces a single history entity.
     * Using {@link OnConflictStrategy#REPLACE} means the cached JSON is always
     * kept up-to-date when the same tx is refetched with richer data.
     */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    void insertOrReplace(TxHistoryEntity entity);

    /**
     * Batch insert / replace – preferred when persisting a full page of results.
     */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    void insertOrReplaceAll(List<TxHistoryEntity> entities);

    // ── Read ───────────────────────────────────────────────────────────────

    /**
     * Returns up to {@code limit} history entries for the given wallet,
     * ordered newest-first by {@code timestamp}.
     */
    @Query("SELECT * FROM tx_history WHERE walletId = :walletId ORDER BY timestamp DESC LIMIT :limit")
    List<TxHistoryEntity> getByWallet(String walletId, int limit);

    /**
     * Returns the total number of cached entries for a wallet.
     * Useful for showing a "loaded from cache" badge while network data is loading.
     */
    @Query("SELECT COUNT(*) FROM tx_history WHERE walletId = :walletId")
    int getCount(String walletId);

    // ── Maintenance ────────────────────────────────────────────────────────

    /** Deletes all cached transactions for a wallet (e.g. when the wallet is removed). */
    @Query("DELETE FROM tx_history WHERE walletId = :walletId")
    void deleteByWallet(String walletId);

    /**
     * Prunes entries for a wallet so that at most 500 rows are kept.
     * Rows with the lowest {@code timestamp} (oldest) are deleted first.
     *
     * <p>Safe to call repeatedly; is a no-op when the entry count is &le;500.</p>
     */
    @Query(
        "DELETE FROM tx_history " +
        "WHERE walletId = :walletId " +
        "AND rowKey NOT IN (" +
        "  SELECT rowKey FROM tx_history " +
        "  WHERE walletId = :walletId " +
        "  ORDER BY timestamp DESC " +
        "  LIMIT 500" +
        ")"
    )
    void pruneOldEntries(String walletId);
}
