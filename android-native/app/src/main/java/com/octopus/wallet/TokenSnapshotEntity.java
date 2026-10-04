package com.octopus.wallet;

import androidx.annotation.NonNull;
import androidx.room.Entity;
import androidx.room.PrimaryKey;

/**
 * Cached dashboard snapshot used to render balances/tokens quickly while waiting for RPC.
 */
@Entity(tableName = "token_snapshot")
public class TokenSnapshotEntity {

    @PrimaryKey
    @NonNull
    public String walletId;

    public long totalRaw;
    public long publicRaw;
    public long encryptedRaw;

    /** JSON array string of token rows. */
    public String tokensJson;

    /** Unix epoch millis for cache freshness checks/debugging. */
    public long updatedAt;

    public TokenSnapshotEntity() {
        walletId = "";
    }

    public static TokenSnapshotEntity create(
            String walletId,
            long totalRaw,
            long publicRaw,
            long encryptedRaw,
            String tokensJson,
            long updatedAt
    ) {
        TokenSnapshotEntity entity = new TokenSnapshotEntity();
        entity.walletId = walletId == null ? "" : walletId;
        entity.totalRaw = totalRaw;
        entity.publicRaw = publicRaw;
        entity.encryptedRaw = encryptedRaw;
        entity.tokensJson = tokensJson == null ? "[]" : tokensJson;
        entity.updatedAt = updatedAt;
        return entity;
    }
}
