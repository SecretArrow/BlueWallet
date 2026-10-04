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
            // Prefer pending_nonce (webcli parity) so in-flight txs get the
            // right sequence; fall back to 0 like before when absent.
            int    nonce   = selectNonce(balResult, 0);

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
            return selectFee(root, category, fallback);
        } catch (Exception e) {
            return fallback;
        }
    }

    /**
     * Pick the recommended fee out of a fee-structure object. Non-positive,
     * missing or malformed buckets yield {@code fallback} (never ≤ 0 unless
     * the fallback itself is). Package-visible for tests.
     */
    static long selectFee(JSONObject root, String category, long fallback) {
        try {
            if (root == null || category == null) return fallback;
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
        if (balResult.has("pending_nonce") || balResult.has("nonce")) {
            return selectNonce(balResult, 0);
        }
        JSONObject account = balResult.optJSONObject("account");
        if (account != null && (account.has("pending_nonce") || account.has("nonce"))) {
            return selectNonce(account, 0);
        }
        throw new IllegalStateException("Invalid balance response: missing 'nonce'");
    }

    /**
     * Select the usable nonce from a balance/account object. Prefers
     * {@code pending_nonce} (counts in-flight transactions, webcli parity),
     * falls back to {@code nonce}, then to {@code fallback}. Accepts numbers
     * and numeric strings; negative or unparsable values yield {@code fallback}
     * clamped at zero — a nonce must never go negative.
     * Package-visible for tests.
     */
    static int selectNonce(JSONObject obj, int fallback) {
        if (obj == null) return Math.max(0, fallback);
        long v = readLongField(obj, "pending_nonce", Long.MIN_VALUE);
        if (v == Long.MIN_VALUE) v = readLongField(obj, "nonce", Long.MIN_VALUE);
        if (v == Long.MIN_VALUE) return Math.max(0, fallback);
        if (v < 0) return 0;
        if (v > Integer.MAX_VALUE) return Integer.MAX_VALUE;
        return (int) v;
    }

    /** Read a JSON field as long (number or numeric string); {@code missing} when absent/invalid/null. */
    static long readLongField(JSONObject obj, String key, long missing) {
        try {
            if (obj == null || !obj.has(key) || obj.isNull(key)) return missing;
            Object v = obj.get(key);
            if (v instanceof Number) return ((Number) v).longValue();
            String s = v.toString().trim();
            if (s.isEmpty()) return missing;
            return Long.parseLong(s);
        } catch (Exception e) {
            return missing;
        }
    }

    // ── Submit ─────────────────────────────────────────────────────────────

    /**
     * Submits a signed transaction to the node.
     *
     * @return the tx hash returned by the node (never empty)
     * @throws IllegalStateException if the node response carries no tx hash —
     *         callers must treat this as a failed submit, never as success
     */
    public String submitTx(String rpcUrl, JSONObject signedTx) throws Exception {
        JSONObject result = rpc.submitTx(rpcUrl, signedTx);
        String hash = result == null ? "" : result.optString("tx_hash", "").trim();
        if (hash.isEmpty()) {
            throw new IllegalStateException("Node submit returned no tx_hash"
                    + (result == null ? " (null result)" : ": " + result.toString()));
        }
        return hash;
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

        // Register (webcli sends aes_kat as 5th param — include it when available)
        String regSig = OctraNative.getInstance().signPvacRegister();
        String pubKeyB64 = OctraNative.getInstance().getPublicKeyB64();
        if (regSig.isEmpty() || pubKeyB64.isEmpty()) {
            throw new IllegalStateException("Failed to sign pvac registration");
        }
        String aesKat = "";
        try {
            aesKat = OctraNative.getInstance().computeAesKat();
        } catch (Exception e) {
            Log.w(TAG, "computeAesKat failed, registering without kat: " + e.getMessage());
        }
        rpc.registerPvacPubkey(rpcUrl, address, localPk, regSig, pubKeyB64,
                aesKat == null ? "" : aesKat);
        Log.d(TAG, "pvac pubkey registered successfully");
    }

    /**
     * Submits a PVAC encryption-key rotation ({@code op_type:key_switch}),
     * mirroring webcli {@code POST /api/key_switch}.
     *
     * <p>Builds the tx via {@code signGeneralTransaction} (self-transfer,
     * amount 0, ou 3000) so the nonce is set correctly before signing —
     * the legacy {@code signKeySwitchTx} JNI signs with nonce 0.</p>
     *
     * @return node submit result (contains {@code tx_hash} on success)
     */
    public JSONObject submitKeySwitch(String rpcUrl, String address) throws Exception {
        String localPk = OctraNative.getInstance().getPvacPubkey();
        if (localPk == null || localPk.isEmpty()) {
            throw new IllegalStateException("PVAC not available");
        }
        String aesKat = OctraNative.getInstance().computeAesKat();
        if (aesKat == null) aesKat = "";

        // message = "encryption key switch | new_key:<sha256(pubkey)[0:8]hex>"
        byte[] pkRaw = OctraNative.getInstance().base64Decode(localPk);
        byte[] digest = sha256(pkRaw);
        StringBuilder hex = new StringBuilder();
        for (int i = 0; i < 8 && i < digest.length; i++) {
            hex.append(String.format("%02x", digest[i] & 0xff));
        }
        String message = "encryption key switch | new_key:" + hex;

        JSONObject encData = new JSONObject();
        encData.put("new_pubkey", localPk);
        encData.put("aes_kat", aesKat);

        Result<BalanceSummary> bal = fetchBalance(rpcUrl, address);
        if (!bal.isSuccess()) {
            throw new IllegalStateException("Failed to fetch balance/nonce: " + bal.getError());
        }
        int nextNonce = bal.getValue().nonce + 1;

        // OU from the fee oracle (upstream webcli parity), fallback 3000.
        String ou = fetchRecommendedOu(rpcUrl, "key_switch", "3000");

        String signedTxStr = OctraNative.getInstance().signGeneralTransaction(
                address, "0", nextNonce, ou, "key_switch", message, encData.toString());
        if (signedTxStr == null || signedTxStr.isEmpty()) {
            throw new IllegalStateException("Failed to sign key_switch transaction");
        }
        JSONObject signedTx = new JSONObject(signedTxStr);
        if (signedTx.has("error")) {
            throw new IllegalStateException(signedTx.optString("error", "Failed to sign key_switch"));
        }
        return rpc.submitTx(rpcUrl, signedTx);
    }

    private byte[] sha256(byte[] data) throws Exception {
        java.security.MessageDigest md = java.security.MessageDigest.getInstance("SHA-256");
        return md.digest(data);
    }

    /**
     * Recommended OU for a single op via {@code octra_recommendedFee([op])}.
     * Never throws — returns {@code fallback} on any failure.
     */
    public String fetchRecommendedOu(String rpcUrl, String op, String fallback) {
        try {
            JSONObject bucket = rpc.fetchFeeForOp(rpcUrl, op);
            if (bucket != null) {
                String rec = bucket.optString("recommended", "");
                if (!rec.isEmpty() && Long.parseLong(rec) > 0) return rec;
            }
        } catch (Exception e) {
            Log.w(TAG, "fetchRecommendedOu(" + op + ") failed: " + e.getMessage());
        }
        return fallback;
    }

    /**
     * Batch fee estimation for all op types (webcli {@code GET /api/fee}
     * parity). Never throws — falls back per-op inside the RPC client.
     */
    public JSONObject fetchFeeBatch(String rpcUrl) {
        try {
            return rpc.fetchFeeBatch(rpcUrl);
        } catch (Exception e) {
            Log.w(TAG, "fetchFeeBatch failed: " + e.getMessage());
            return new JSONObject();
        }
    }

    /**
     * Fast token listing via {@code octra_tokensByAddress} (webcli
     * {@code GET /api/tokens} parity). Returns raw token array; callers
     * fall back to {@code listContracts} probing when empty.
     */
    public JSONArray fetchTokensFast(String rpcUrl, String address) {
        try {
            return rpc.getTokensByAddress(rpcUrl, address);
        } catch (Exception e) {
            Log.w(TAG, "fetchTokensFast failed, caller should probe listContracts: " + e.getMessage());
            return new JSONArray();
        }
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
