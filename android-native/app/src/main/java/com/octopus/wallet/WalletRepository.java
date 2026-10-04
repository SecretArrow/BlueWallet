package com.octopus.wallet;

import android.content.Context;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.List;

/**
 * Data layer — all network, native, and Room-DB operations for wallet data.
 *
 * <p>Network calls are delegated to the singleton {@link OctraRpcClient} so
 * that connection pooling, retry logic, and URL normalisation live in exactly
 * one place.  {@code WalletRepository} adds domain semantics on top (native
 * calls via {@link OctraNative}, Room caching, balance decryption, etc.).</p>
 *
 * <p>This class is intentionally framework-free so it can be used from both
 * a {@link WalletViewModel} and, for now, directly from Activities / Services
 * while the MVVM migration is in progress.</p>
 *
 * <p>Threading: every method is safe to call from a background thread.</p>
 */
public final class WalletRepository {

    private static final String TAG = "WalletRepository";

    private final OctraRpcClient rpc = OctraRpcClient.getInstance();
    private final Context appContext;

    // ── Public result wrappers ─────────────────────────────────────────────

    /** Typed result — either a value or an error message. */
    public static final class Result<T> {
        private final T value;
        private final String error;

        private Result(T value, String error) {
            this.value = value;
            this.error = error;
        }

        public static <T> Result<T> success(T value)   { return new Result<>(value, null);  }
        public static <T> Result<T> failure(String err) { return new Result<>(null, err);    }

        public boolean isSuccess() { return error == null; }
        public T getValue()        { return value; }
        public String getError()   { return error; }
    }

    /** Represents a wallet's balance summary. */
    public static final class BalanceSummary {
        public final long publicRaw;
        public final long encryptedRaw;
        public final long totalRaw;
        public final int  nonce;

        public BalanceSummary(long publicRaw, long encryptedRaw, int nonce) {
            this.publicRaw    = publicRaw;
            this.encryptedRaw = encryptedRaw;
            this.totalRaw     = publicRaw + encryptedRaw;
            this.nonce        = nonce;
        }
    }

    /** Cached dashboard snapshot (native balances + rendered token rows). */
    public static final class TokenSnapshot {
        public final long totalRaw;
        public final long publicRaw;
        public final long encryptedRaw;
        public final JSONArray tokens;
        public final long updatedAt;

        public TokenSnapshot(long totalRaw, long publicRaw, long encryptedRaw, JSONArray tokens, long updatedAt) {
            this.totalRaw = totalRaw;
            this.publicRaw = publicRaw;
            this.encryptedRaw = encryptedRaw;
            this.tokens = tokens == null ? new JSONArray() : tokens;
            this.updatedAt = updatedAt;
        }
    }

    // ── Constructor ────────────────────────────────────────────────────────

    public WalletRepository(Context context) {
        this.appContext = context.getApplicationContext();
    }

    // ── Native wallet info ─────────────────────────────────────────────────

    /** Returns the current wallet's info JSON from native, or an error result. */
    public Result<JSONObject> getWalletInfo() {
        try {
            String raw = OctraNative.getInstance().getWalletInfo();
            JSONObject info = new JSONObject(raw);
            if (info.has("error")) {
                return Result.failure(info.optString("error", "Wallet not available"));
            }
            return Result.success(info);
        } catch (Exception e) {
            return Result.failure("Failed to get wallet info: " + e.getMessage());
        }
    }

    // ── Balance ────────────────────────────────────────────────────────────

    /**
     * Fetches the full balance summary (public + encrypted) for the given address.
     *
     * <p>The public balance comes from {@code octra_balance} which returns
     * {@code balance_raw} (string) and {@code nonce} (int).  Note that this
     * RPC method does <b>not</b> include an {@code encrypted_balance} field.</p>
     *
     * <p>The encrypted balance requires a separate authenticated call:
     * {@code octra_encryptedBalance(address, signature, pubkey)} → {@code {"cipher":"..."}}
     * which is then decrypted locally via the PVAC subsystem.  This mirrors the
     * webcli reference implementation in {@code get_encrypted_balance()}.</p>
     *
     * <p>Must be called from a background thread.</p>
     */
    public Result<BalanceSummary> fetchBalance(String rpcUrl, String address) {
        try {
            JSONObject balResult = rpc.getBalance(rpcUrl, address);
            String balRaw  = balResult.optString("balance_raw", "0");
            int    nonce   = balResult.optInt("nonce", 0);

            long publicRaw = parseLong(balRaw);
            long encRaw    = 0L;

            // Fetch encrypted balance via the dedicated authenticated RPC method.
            // octra_balance does NOT contain encrypted_balance — it's a separate call.
            try {
                String cipher = fetchEncryptedBalance(rpcUrl, address);
                if (cipher != null && !cipher.isEmpty() && !"0".equals(cipher)) {
                    // Try to parse as a plain number first (already-decrypted value)
                    long directVal = parseLong(cipher);
                    if (directVal > 0) {
                        encRaw = directVal;
                    } else {
                        // It's a PVAC cipher — decrypt locally
                        encRaw = OctraNative.getInstance().decryptEncryptedBalanceCipher(cipher);
                    }
                }
            } catch (Exception e) {
                Log.w(TAG, "Encrypted balance fetch failed (non-fatal): " + e.getMessage());
                // Non-fatal: encrypted balance is optional, public balance still valid
            }

            return Result.success(new BalanceSummary(publicRaw, Math.max(encRaw, 0L), nonce));
        } catch (Exception e) {
            return Result.failure("Balance fetch failed: " + e.getMessage());
        }
    }

    // ── Transaction history ────────────────────────────────────────────────

    /**
     * Fetches a page of transaction history for the given address.
     * Uses {@code octra_transactionsByAddress} which is the proper paginated
     * history method (matching the webcli reference implementation).
     * Returns an empty list on failure rather than an error result, so callers
     * can render cached data while a network error occurs.
     */
    public List<JSONObject> fetchHistory(String rpcUrl, String address, int limit, int offset) {
        List<JSONObject> out = new ArrayList<>();
        try {
            JSONObject result = rpc.getTransactionsByAddress(rpcUrl, address, limit, offset);

            JSONArray txs = null;
            if (result.has("transactions")) txs = result.optJSONArray("transactions");
            else if (result.has("history"))  txs = result.optJSONArray("history");
            else if (result.has("txs"))      txs = result.optJSONArray("txs");

            if (txs != null) {
                for (int i = 0; i < txs.length(); i++) {
                    JSONObject tx = txs.optJSONObject(i);
                    if (tx != null) out.add(tx);
                }
            }
        } catch (Exception e) {
            Log.w(TAG, "fetchHistory failed: " + e.getMessage());
        }
        return out;
    }

    /**
     * Fetches token transfer history for a given address.
     * Tries the node's native token transfers RPC endpoint first, and falls back to scanning/filtering.
     */
    public List<JSONObject> fetchTokenHistory(String rpcUrl, String address, int limit, int offset) {
        List<JSONObject> out = new ArrayList<>();
        try {
            try {
                JSONObject result = rpc.getTokenTransfersByAddress(rpcUrl, address, limit, offset);
                JSONArray txs = null;
                if (result.has("transactions")) txs = result.optJSONArray("transactions");
                else if (result.has("history"))  txs = result.optJSONArray("history");
                else if (result.has("txs"))      txs = result.optJSONArray("txs");

                if (txs != null) {
                    for (int i = 0; i < txs.length(); i++) {
                        JSONObject tx = txs.optJSONObject(i);
                        if (tx != null) out.add(tx);
                    }
                    return out;
                }
            } catch (Exception e) {
                Log.w(TAG, "getTokenTransfersByAddress RPC failed: " + e.getMessage() + ", falling back to scanning general txs");
            }

            // Fallback: Scan general transactions
            JSONObject result = rpc.getTransactionsByAddress(rpcUrl, address, Math.max(limit * 5, 100), 0);
            JSONArray txs = null;
            if (result.has("transactions")) txs = result.optJSONArray("transactions");
            else if (result.has("history"))  txs = result.optJSONArray("history");
            else if (result.has("txs"))      txs = result.optJSONArray("txs");

            if (txs != null) {
                int matchedCount = 0;
                for (int i = 0; i < txs.length(); i++) {
                    JSONObject tx = txs.optJSONObject(i);
                    if (tx == null) continue;

                    String opType = tx.optString("op_type", "");
                    String encData = tx.optString("encrypted_data", "");
                    if (!"call".equals(opType)) continue;
                    if (!"transfer".equals(encData)) continue;

                    if (matchedCount >= offset && out.size() < limit) {
                        out.add(tx);
                    }
                    matchedCount++;
                }
            }
        } catch (Exception e) {
            Log.w(TAG, "fetchTokenHistory fallback failed: " + e.getMessage());
        }
        return out;
    }

    // ── Recommended fee ────────────────────────────────────────────────────

    /** Returns the recommended fee for the given category, or the fallback on error. */
    public long fetchRecommendedFee(String rpcUrl, String category, long fallback) {
        try {
            JSONObject root = rpc.fetchFee(rpcUrl);
            if (root == null) return fallback;
            JSONObject bucket = root.optJSONObject(category);
            if (bucket == null) return fallback;
            long fee = parseLong(bucket.optString("recommended", String.valueOf(fallback)));
            return fee > 0 ? fee : fallback;
        } catch (Exception e) {
            return fallback;
        }
    }

    // ── Formatting helpers (usable by VM / Activity) ───────────────────────

    public static String formatOct(long rawMicrocoins) {
        BigDecimal v = BigDecimal.valueOf(rawMicrocoins, 6)
                .setScale(6, RoundingMode.DOWN)
                .stripTrailingZeros();
        if (v.scale() < 0) v = v.setScale(0);
        return v.toPlainString();
    }

    // ── Room history cache ─────────────────────────────────────────────────

    /**
     * Persists a list of transaction JSON objects to the Room database for offline access.
     * Must be called from a background thread.
     *
     * @param walletId wallet profile identifier
     * @param txs      list of full transaction JSON objects (may include synthetic local fields)
     */
    public void saveHistoryToRoom(String walletId, List<JSONObject> txs) {
        if (walletId == null || walletId.isEmpty() || txs == null || txs.isEmpty()) return;
        try {
            List<TxHistoryEntity> entities = new ArrayList<>(txs.size());
            for (JSONObject tx : txs) {
                if (tx == null) continue;
                String hash = firstNonEmptyStr(
                        tx.optString("hash", ""),
                        tx.optString("tx_hash", "")).trim();
                // Use a synthetic key for entries without a real hash (local pending items).
                if (hash.isEmpty()) {
                    hash = "local_" + tx.optLong("local_ts", System.currentTimeMillis());
                }
                long ts = tx.optLong("local_ts", 0L);
                if (ts <= 0L) {
                    String rawTs = firstNonEmptyStr(
                            tx.optString("timestamp", ""),
                            tx.optString("time", ""),
                            tx.optString("created_at", ""));
                    try { ts = (long)(Double.parseDouble(rawTs) * 1000); } catch (Exception ignored) {}
                }
                entities.add(TxHistoryEntity.create(walletId, hash, tx.toString(), ts));
            }
            OctraDatabase.get(appContext).txHistoryDao().insertOrReplaceAll(entities);
            OctraDatabase.get(appContext).txHistoryDao().pruneOldEntries(walletId);
        } catch (Exception e) {
            Log.w(TAG, "saveHistoryToRoom failed: " + e.getMessage());
        }
    }

    /**
     * Loads up to {@code limit} cached transaction JSON objects from Room, ordered newest-first.
     * Returns an empty list on failure rather than throwing so callers render cached data
     * gracefully while the network is unavailable.
     *
     * @param walletId wallet profile identifier
     * @param limit    maximum number of entries to return
     */
    public List<JSONObject> loadHistoryFromRoom(String walletId, int limit) {
        List<JSONObject> out = new ArrayList<>();
        if (walletId == null || walletId.isEmpty()) return out;
        try {
            List<TxHistoryEntity> rows =
                    OctraDatabase.get(appContext).txHistoryDao().getByWallet(walletId, limit);
            for (TxHistoryEntity row : rows) {
                try { out.add(new JSONObject(row.txJson)); } catch (Exception ignored) {}
            }
        } catch (Exception e) {
            Log.w(TAG, "loadHistoryFromRoom failed: " + e.getMessage());
        }
        return out;
    }

    private static String firstNonEmptyStr(String... vals) {
        for (String v : vals) if (v != null && !v.trim().isEmpty()) return v;
        return "";
    }

    // ── Room token snapshot cache ────────────────────────────────────────

    /**
     * Saves a dashboard token snapshot for the given wallet.
     * Must be called from a background thread.
     */
    public void saveTokenSnapshotToRoom(
            String walletId,
            long totalRaw,
            long publicRaw,
            long encryptedRaw,
            JSONArray tokens
    ) {
        if (walletId == null || walletId.trim().isEmpty()) return;
        try {
            String tokensJson = tokens == null ? "[]" : tokens.toString();
            TokenSnapshotEntity entity = TokenSnapshotEntity.create(
                    walletId.trim(),
                    totalRaw,
                    publicRaw,
                    encryptedRaw,
                    tokensJson,
                    System.currentTimeMillis());
            OctraDatabase.get(appContext).tokenSnapshotDao().upsert(entity);
        } catch (Exception e) {
            Log.w(TAG, "saveTokenSnapshotToRoom failed: " + e.getMessage());
        }
    }

    /**
     * Loads cached balance/token snapshot for a wallet.
     * Returns null when not available.
     */
    public TokenSnapshot loadTokenSnapshotFromRoom(String walletId) {
        if (walletId == null || walletId.trim().isEmpty()) return null;
        try {
            TokenSnapshotEntity entity =
                    OctraDatabase.get(appContext).tokenSnapshotDao().getByWallet(walletId.trim());
            if (entity == null) return null;
            JSONArray rows;
            try {
                rows = new JSONArray(entity.tokensJson == null ? "[]" : entity.tokensJson);
            } catch (Exception ignored) {
                rows = new JSONArray();
            }
            return new TokenSnapshot(
                    entity.totalRaw,
                    entity.publicRaw,
                    entity.encryptedRaw,
                    rows,
                    entity.updatedAt);
        } catch (Exception e) {
            Log.w(TAG, "loadTokenSnapshotFromRoom failed: " + e.getMessage());
            return null;
        }
    }

    // ── Internal ───────────────────────────────────────────────────────────

    // ── Nonce ──────────────────────────────────────────────────────────────

    /**
     * Fetches the current nonce for the given address (from octra_balance).
     * Must be called from a background thread.
     */
    public int fetchNonce(String rpcUrl, String address) throws Exception {
        JSONObject balResult = rpc.getBalance(rpcUrl, address);
        if (balResult.has("nonce")) {
            return balResult.optInt("nonce", 0);
        }
        JSONObject account = balResult.optJSONObject("account");
        if (account != null && account.has("nonce")) {
            return account.optInt("nonce", 0);
        }
        throw new IllegalStateException("Invalid balance response: missing 'nonce'");
    }

    // ── Submit ─────────────────────────────────────────────────────────────

    /**
     * Submits a signed transaction to the node.
     *
     * @return the tx hash returned by the node
     */
    public String submitTx(String rpcUrl, JSONObject signedTx) throws Exception {
        JSONObject result = rpc.submitTx(rpcUrl, signedTx);
        return result == null ? "" : result.optString("tx_hash", "");
    }

    // ── Privacy (PVAC) ─────────────────────────────────────────────────────

    /**
     * Ensures the PVAC public key is registered on the blockchain.
     * If already registered with the same key, this is a no-op.
     */
    public void ensurePvacRegistered(String rpcUrl, String address) throws Exception {
        String localPk = OctraNative.getInstance().getPvacPubkey();
        if (localPk == null || localPk.isEmpty()) {
            throw new IllegalStateException("PVAC not available");
        }

        // Check if already registered
        JSONObject existing = rpc.getPvacPubkey(rpcUrl, address);
        if (existing != null && existing.has("pvac_pubkey")
                && !existing.isNull("pvac_pubkey")) {
            String remotePk = existing.getString("pvac_pubkey");
            if (localPk.equals(remotePk)) {
                Log.d(TAG, "pvac pubkey already registered");
                return;
            }
        }

        // Register
        String regSig = OctraNative.getInstance().signPvacRegister();
        String pubKeyB64 = OctraNative.getInstance().getPublicKeyB64();
        if (regSig.isEmpty() || pubKeyB64.isEmpty()) {
            throw new IllegalStateException("Failed to sign pvac registration");
        }
        rpc.registerPvacPubkey(rpcUrl, address, localPk, regSig, pubKeyB64);
        Log.d(TAG, "pvac pubkey registered successfully");
    }

    // ── Encrypted balance ──────────────────────────────────────────────────

    /**
     * Fetches the encrypted balance cipher for the given address.
     *
     * @return cipher string, or "0" if unavailable
     */
    public String fetchEncryptedBalance(String rpcUrl, String address) throws Exception {
        String sig = OctraNative.getInstance().signBalanceRequest();
        String pubB64 = OctraNative.getInstance().getPublicKeyB64();

        JSONObject result = rpc.getEncryptedBalance(rpcUrl, address, sig, pubB64);
        if (result == null) return "0";
        return result.optString("cipher", "0");
    }

    // ── View pubkey ────────────────────────────────────────────────────────

    /**
     * Fetches the view public key for a given address.
     *
     * @throws IllegalStateException if the address has no registered view pubkey
     */
    public String fetchViewPubkey(String rpcUrl, String address) throws Exception {
        JSONObject result = rpc.getViewPubkey(rpcUrl, address);
        if (result == null || !result.has("view_pubkey") || result.isNull("view_pubkey")) {
            throw new IllegalStateException("Recipient has no view pubkey");
        }
        return result.getString("view_pubkey");
    }

    // ── Transaction lookup ─────────────────────────────────────────────────

    /**
     * Fetches a single transaction by hash.
     *
     * @return the transaction JSON, or {@code null} if not found
     */
    public JSONObject fetchTransaction(String rpcUrl, String txHash) throws Exception {
        return rpc.getTransaction(rpcUrl, txHash);
    }

    // ── Stealth outputs ────────────────────────────────────────────────────

    /**
     * Scans for incoming stealth payments from the given epoch.
     *
     * @return array of stealth output objects
     */
    public JSONArray fetchStealthOutputs(String rpcUrl, int fromEpoch) throws Exception {
        return rpc.getStealthOutputs(rpcUrl, fromEpoch);
    }

    /**
     * Overload accepting address for call-site compatibility.
     */
    public JSONArray fetchStealthOutputs(String rpcUrl, String address) throws Exception {
        // Address is used for local filtering — the RPC method scans by epoch.
        // Default to epoch 0 when called by address only.
        return rpc.getStealthOutputs(rpcUrl, 0);
    }

    // ── Smart contracts ────────────────────────────────────────────────────

    /** Lists all deployed contracts. */
    public JSONObject listContracts(String rpcUrl) throws Exception {
        return rpc.listContracts(rpcUrl);
    }

    /** Reads a single storage key from a contract. */
    public String contractStorage(String rpcUrl, String contractAddr, String key)
            throws Exception {
        return rpc.contractStorage(rpcUrl, contractAddr, key);
    }

    /** Calls a read-only (view) method on a contract. */
    public JSONObject contractView(String rpcUrl, String contractAddr,
                                    String method, JSONArray args, String caller)
            throws Exception {
        return rpc.contractView(rpcUrl, contractAddr, method, args, caller);
    }

    private static long parseLong(String s) {
        if (s == null || s.trim().isEmpty()) return 0L;
        try { return Long.parseLong(s.trim()); } catch (Exception ignored) { return 0L; }
    }
}
