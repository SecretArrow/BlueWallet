package com.octopus.wallet;

import androidx.room.Dao;
import androidx.room.Insert;
import androidx.room.OnConflictStrategy;
import androidx.room.Query;

@Dao
public interface TokenSnapshotDao {

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    void upsert(TokenSnapshotEntity entity);

    @Query("SELECT * FROM token_snapshot WHERE walletId = :walletId LIMIT 1")
    TokenSnapshotEntity getByWallet(String walletId);

    @Query("DELETE FROM token_snapshot WHERE walletId = :walletId")
    void deleteByWallet(String walletId);
}
