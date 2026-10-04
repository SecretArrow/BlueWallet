package com.octopus.wallet;

import androidx.annotation.NonNull;
import androidx.room.Entity;
import androidx.room.Index;
import androidx.room.PrimaryKey;

/**
 * Room entity representing a single cached transaction history entry.
 *
 * <p>The primary key is "{walletId}:{txHash}" so that the same tx hash can exist
 * independently for different wallets (multi-wallet support).</p>
 *
 * <p>An index on {@code walletId} speeds up the most common query pattern
 * (fetch all txs for a given wallet ordered by timestamp).</p>
 */
@Entity(
        tableName = "tx_history",
        indices = {@Index(value = "walletId")}
)
public class TxHistoryEntity {

    /** Composite primary key: "{walletId}:{txHash}". */
    @PrimaryKey
    @NonNull
    public String rowKey;

    /** The wallet profile identifier this transaction belongs to. */
    @NonNull
    public String walletId;

    /** On-chain transaction hash (may be empty for purely local pending entries). */
    @NonNull
    public String txHash;

    /**
     * Full transaction JSON serialised as a string.  Stored as-is from the RPC response
     * (possibly enriched with local fields such as {@code token_symbol}).
     */
    @NonNull
    public String txJson;

    /**
     * Timestamp in milliseconds since epoch.  Used for ordering.
     * Set to the value of the {@code timestamp} / {@code local_ts} field inside
     * {@code txJson} so that sorting does not require deserialisation.
     */
    public long timestamp;

    /** No-arg constructor required by Room. */
    public TxHistoryEntity() {
        rowKey    = "";
        walletId  = "";
        txHash    = "";
        txJson    = "{}";
        timestamp = 0L;
    }

    // ── Factory ────────────────────────────────────────────────────────────

    /**
     * Creates a fully-populated entity.
     *
     * @param walletId  wallet profile id
     * @param txHash    on-chain hash (or a synthetic key for pending-only entries)
     * @param txJson    full transaction JSON string
     * @param timestamp millisecond epoch timestamp for sorting
     */
    public static TxHistoryEntity create(
            @NonNull String walletId,
            @NonNull String txHash,
            @NonNull String txJson,
            long timestamp) {
        TxHistoryEntity e = new TxHistoryEntity();
        e.rowKey    = walletId + ":" + txHash;
        e.walletId  = walletId;
        e.txHash    = txHash;
        e.txJson    = txJson;
        e.timestamp = timestamp;
        return e;
    }
}
