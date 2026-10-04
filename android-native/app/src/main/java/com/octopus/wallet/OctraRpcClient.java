package com.octopus.wallet;

import android.net.Uri;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;

/**
 * Single-dispatcher JSON-RPC 2.0 client for the Octra blockchain node.
 *
 * <p>Thread-safe.  One shared {@link OkHttpClient} instance is reused across
 * all calls, so connection pooling and keep-alive work correctly even when the
 * caller sits on a foreground service, a WorkManager worker, or a plain
 * background thread launched from an Activity.</p>
 *
 * <h3>Usage</h3>
 * <pre>{@code
 *   OctraRpcClient rpc = OctraRpcClient.getInstance();
 *   JSONObject result  = rpc.call("http://node:8080", "octra_balance",
 *                                  new JSONArray().put(address));
 * }</pre>
 *
 * <p>All public methods are <b>blocking</b> and must be called from a
 * background thread.</p>
 */
public final class OctraRpcClient {

    // ── Singleton ──────────────────────────────────────────────────────────

    private static volatile OctraRpcClient sInstance;

    /** Returns the process-wide singleton.  Thread-safe (double-checked lock). */
    public static OctraRpcClient getInstance() {
        if (sInstance == null) {
            synchronized (OctraRpcClient.class) {
                if (sInstance == null) {
                    sInstance = new OctraRpcClient();
                }
            }
        }
        return sInstance;
    }

    // ── Internal state ─────────────────────────────────────────────────────

    private static final String TAG = "OctraRpcClient";
    private static final MediaType JSON_MEDIA =
            MediaType.get("application/json; charset=utf-8");

    private final OkHttpClient http;
    private final AtomicInteger idSeq = new AtomicInteger(0);

    private OctraRpcClient() {
        http = new OkHttpClient.Builder()
                .connectTimeout(15, TimeUnit.SECONDS)
                .readTimeout(30, TimeUnit.SECONDS)
                .writeTimeout(15, TimeUnit.SECONDS)
                .retryOnConnectionFailure(true)
                .proxySelector(new java.net.ProxySelector() {
                    @Override
                    public java.util.List<java.net.Proxy> select(java.net.URI uri) {
                        try {
                            OctraWalletApplication app = OctraWalletApplication.getInstance();
                            if (app != null && TorProxyStore.isEnabled(app)) {
                                java.net.Proxy proxy = TorProxyStore.getActiveProxy(app);
                                if (proxy != null) {
                                    return java.util.Collections.singletonList(proxy);
                                }
                            }
                        } catch (Exception e) {
                            Log.e(TAG, "ProxySelector error: " + e.getMessage());
                        }
                        return java.util.Collections.singletonList(java.net.Proxy.NO_PROXY);
                    }

                    @Override
                    public void connectFailed(java.net.URI uri, java.net.SocketAddress sa, java.io.IOException ioe) {
                        Log.w(TAG, "Proxy connection failed: " + ioe.getMessage());
                    }
                })
                .build();
    }


    // ════════════════════════════════════════════════════════════════════════
    //  LOW-LEVEL DISPATCH
    // ════════════════════════════════════════════════════════════════════════

    /**
     * Execute a single JSON-RPC 2.0 call.
     *
     * @param rpcUrl base node URL (e.g. {@code http://host:8080})
     * @param method RPC method name
     * @param params JSON array of positional parameters (may be empty)
     * @return the full JSON-RPC response envelope
     * @throws Exception on network or parse error
     */
    public JSONObject call(String rpcUrl, String method, JSONArray params)
            throws Exception {
        JSONObject envelope = new JSONObject();
        envelope.put("jsonrpc", "2.0");
        envelope.put("method", method);
        envelope.put("params", params != null ? params : new JSONArray());
        envelope.put("id", idSeq.incrementAndGet());
        return post(buildRpcEndpoint(rpcUrl), envelope);
    }

    /**
     * Execute a JSON-RPC 2.0 call with automatic retry.
     *
     * @param rpcUrl   base node URL
     * @param method   RPC method name
     * @param params   positional parameters
     * @param attempts maximum number of attempts (≥ 1)
     * @return the full JSON-RPC response envelope
     * @throws Exception the last exception if all retries fail
     */
    public JSONObject callWithRetry(String rpcUrl, String method,
                                    JSONArray params, int attempts)
            throws Exception {
        Exception last = null;
        int max = Math.max(1, attempts);
        for (int i = 1; i <= max; i++) {
            try {
                return call(rpcUrl, method, params);
            } catch (Exception e) {
                last = e;
                if (i < max) {
                    try { Thread.sleep(250L * i); } catch (InterruptedException ignored) {}
                }
            }
        }
        throw (last != null ? last : new IllegalStateException("RPC failed"));
    }

    /**
     * Execute a plain HTTP GET to a REST endpoint on the node.
     *
     * @param url full URL including path
     * @return parsed JSON body
     */
    public JSONObject restGet(String url) throws Exception {
        Request req = new Request.Builder().url(url).get().build();
        try (Response resp = http.newCall(req).execute()) {
            if (resp.body() == null) {
                throw new IllegalStateException("Empty response from " + url);
            }
            return new JSONObject(resp.body().string());
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  TYPED RPC HELPERS  (mirror webcli RpcClient & Flutter WalletService)
    // ════════════════════════════════════════════════════════════════════════

    // ── Balance / Account ─────────────────────────────────────────────────

    /** {@code octra_balance} — returns the full result object. */
    public JSONObject getBalance(String rpcUrl, String address) throws Exception {
        JSONObject root = callWithRetry(rpcUrl, "octra_balance",
                new JSONArray().put(address), 3);
        return extractResult(root);
    }

    /** {@code octra_account} — paginated transaction history. */
    public JSONObject getAccount(String rpcUrl, String address,
                                 int limit, int offset) throws Exception {
        JSONObject root = callWithRetry(rpcUrl, "octra_account",
                new JSONArray().put(address).put(limit).put(offset), 3);
        return extractResult(root);
    }

    /** {@code octra_transaction} — look up a single transaction by hash. */
    public JSONObject getTransaction(String rpcUrl, String txHash) throws Exception {
        JSONObject root = callWithRetry(rpcUrl, "octra_transaction",
                new JSONArray().put(txHash), 3);
        return extractResult(root);
    }

    // ── Submission ────────────────────────────────────────────────────────

    /** {@code octra_submit} — broadcast a signed transaction. */
    public JSONObject submitTx(String rpcUrl, JSONObject signedTx) throws Exception {
        JSONObject root = callWithRetry(rpcUrl, "octra_submit",
                new JSONArray().put(signedTx), 3);
        throwOnRpcError(root);
        return extractResult(root);
    }

    // ── Privacy (PVAC / encrypted balance) ────────────────────────────────

    /** {@code octra_pvacPubkey} — check if a PVAC key is already registered. */
    public JSONObject getPvacPubkey(String rpcUrl, String address) throws Exception {
        JSONObject root = callWithRetry(rpcUrl, "octra_pvacPubkey",
                new JSONArray().put(address), 3);
        return extractResultOrNull(root);
    }

    /** {@code octra_registerPvacPubkey} — register a new PVAC public key. */
    public JSONObject registerPvacPubkey(String rpcUrl, String address,
                                         String pvacPk, String signature,
                                         String pubKeyB64) throws Exception {
        return registerPvacPubkey(rpcUrl, address, pvacPk, signature, pubKeyB64, "");
    }

    /**
     * {@code octra_registerPvacPubkey} — register a new PVAC public key,
     * including the AES-KAT hex (mirrors webcli {@code register_pvac_pubkey}
     * which sends {@code [addr, pk_b64, sig_b64, pub_b64, aes_kat_hex]}).
     */
    public JSONObject registerPvacPubkey(String rpcUrl, String address,
                                         String pvacPk, String signature,
                                         String pubKeyB64, String aesKatHex) throws Exception {
        JSONArray p = new JSONArray();
        p.put(address).put(pvacPk).put(signature).put(pubKeyB64);
        if (aesKatHex != null && !aesKatHex.isEmpty()) p.put(aesKatHex);
        JSONObject root = callWithRetry(rpcUrl, "octra_registerPvacPubkey", p, 3);
        throwOnRpcError(root);
        return extractResultOrNull(root);
    }

    /** {@code octra_encryptedBalance} — fetch the encrypted balance cipher. */
    public JSONObject getEncryptedBalance(String rpcUrl, String address,
                                           String signature,
                                           String pubKeyB64) throws Exception {
        JSONArray p = new JSONArray();
        p.put(address).put(signature).put(pubKeyB64);
        JSONObject root = callWithRetry(rpcUrl, "octra_encryptedBalance", p, 3);
        return extractResultOrNull(root);
    }

    /** {@code octra_encryptedCipher} — fetch the raw encrypted cipher. */
    public JSONObject getEncryptedCipher(String rpcUrl, String address)
            throws Exception {
        JSONObject root = callWithRetry(rpcUrl, "octra_encryptedCipher",
                new JSONArray().put(address), 3);
        return extractResultOrNull(root);
    }

    // ── View / Stealth ────────────────────────────────────────────────────

    /** {@code octra_viewPubkey} — retrieve a view public key. */
    public JSONObject getViewPubkey(String rpcUrl, String address)
            throws Exception {
        JSONObject root = callWithRetry(rpcUrl, "octra_viewPubkey",
                new JSONArray().put(address), 3);
        throwOnRpcError(root);
        return extractResult(root);
    }

    /** {@code octra_registerViewPubkey} — register a view public key. */
    public JSONObject registerViewPubkey(String rpcUrl, String address,
                                          String viewPk, String signature,
                                          String pubKeyB64) throws Exception {
        JSONArray p = new JSONArray();
        p.put(address).put(viewPk).put(signature).put(pubKeyB64);
        JSONObject root = callWithRetry(rpcUrl, "octra_registerViewPubkey", p, 3);
        throwOnRpcError(root);
        return extractResultOrNull(root);
    }

    /** {@code octra_stealthOutputs} — scan for incoming stealth payments. */
    public JSONArray getStealthOutputs(String rpcUrl, int fromEpoch)
            throws Exception {
        JSONObject root = callWithRetry(rpcUrl, "octra_stealthOutputs",
                new JSONArray().put(fromEpoch), 3);
        if (root.has("result")) {
            Object r = root.get("result");
            if (r instanceof JSONArray) return (JSONArray) r;
            if (r instanceof JSONObject) {
                JSONObject ro = (JSONObject) r;
                if (ro.has("outputs")) return ro.optJSONArray("outputs");
            }
        }
        return new JSONArray();
    }

    // ── Smart Contracts ───────────────────────────────────────────────────

    /** {@code octra_listContracts} — list all deployed contracts. */
    public JSONObject listContracts(String rpcUrl) throws Exception {
        JSONObject root = callWithRetry(rpcUrl, "octra_listContracts",
                new JSONArray(), 2);
        return extractResult(root);
    }

    /** {@code octra_contractStorage} — read a single storage key. */
    public String contractStorage(String rpcUrl, String contractAddr,
                                   String key) throws Exception {
        JSONObject root = callWithRetry(rpcUrl, "octra_contractStorage",
                new JSONArray().put(contractAddr).put(key), 2);
        JSONObject result = extractResultOrNull(root);
        if (result == null) return null;
        return result.optString("value",
                result.optString("result", null));
    }

    /** {@code contract_call} — invoke a read-only (view) contract method. */
    public JSONObject contractView(String rpcUrl, String contractAddr,
                                    String method, JSONArray args,
                                    String caller) throws Exception {
        JSONArray p = new JSONArray();
        p.put(contractAddr).put(method).put(args).put(caller);
        JSONObject root = callWithRetry(rpcUrl, "contract_call", p, 2);
        return extractResultOrNull(root);
    }

    /** {@code octra_compileAssembly} — compile assembly source. */
    public JSONObject compileAssembly(String rpcUrl, String source)
            throws Exception {
        JSONObject root = call(rpcUrl, "octra_compileAssembly",
                new JSONArray().put(source));
        throwOnRpcError(root);
        return extractResult(root);
    }

    /** {@code octra_compileAml} — compile AML source. */
    public JSONObject compileAml(String rpcUrl, String source)
            throws Exception {
        JSONObject root = call(rpcUrl, "octra_compileAml",
                new JSONArray().put(source));
        throwOnRpcError(root);
        return extractResult(root);
    }

    /** {@code octra_computeContractAddress} — compute deterministic address. */
    public JSONObject computeContractAddress(String rpcUrl, String bytecodeB64,
                                              String deployer, int nonce)
            throws Exception {
        JSONObject root = call(rpcUrl, "octra_computeContractAddress",
                new JSONArray().put(bytecodeB64).put(deployer).put(nonce));
        return extractResult(root);
    }

    /** {@code vm_contract} — get deployed contract info. */
    public JSONObject vmContract(String rpcUrl, String contractAddr)
            throws Exception {
        JSONObject root = callWithRetry(rpcUrl, "vm_contract",
                new JSONArray().put(contractAddr), 2);
        return extractResultOrNull(root);
    }

    /** {@code contract_receipt} — get contract execution receipt. */
    public JSONObject contractReceipt(String rpcUrl, String txHash)
            throws Exception {
        JSONObject root = callWithRetry(rpcUrl, "contract_receipt",
                new JSONArray().put(txHash), 2);
        return extractResultOrNull(root);
    }

    /** {@code octra_contractAbi} — get contract ABI. */
    public JSONObject contractAbi(String rpcUrl, String contractAddr)
            throws Exception {
        JSONObject root = callWithRetry(rpcUrl, "octra_contractAbi",
                new JSONArray().put(contractAddr), 2);
        return extractResultOrNull(root);
    }

    /** {@code contract_saveAbi} — save/update contract ABI. */
    public JSONObject saveAbi(String rpcUrl, String contractAddr, String abi)
            throws Exception {
        JSONObject root = call(rpcUrl, "contract_saveAbi",
                new JSONArray().put(contractAddr).put(abi));
        throwOnRpcError(root);
        return extractResultOrNull(root);
    }

    /** {@code octra_verifyContract} — submit a contract verification request. */
    public JSONObject verifyContract(String rpcUrl, String contractAddr,
                                      String source) throws Exception {
        JSONObject root = call(rpcUrl, "octra_verifyContract",
                new JSONArray().put(contractAddr).put(source));
        throwOnRpcError(root);
        return extractResultOrNull(root);
    }

    /** {@code octra_transactionsByAddress} — paginated tx lookup by addr. */
    public JSONObject getTransactionsByAddress(String rpcUrl, String address,
                                               int limit, int offset)
            throws Exception {
        JSONArray p = new JSONArray();
        p.put(address).put(limit).put(offset);
        JSONObject root = callWithRetry(rpcUrl, "octra_transactionsByAddress", p, 2);
        return extractResult(root);
    }

    /** {@code octra_tokenTransfersByAddress} — paginated token tx lookup. */
    public JSONObject getTokenTransfersByAddress(String rpcUrl, String address,
                                                 int limit, int offset)
            throws Exception {
        JSONArray p = new JSONArray();
        p.put(address).put(limit).put(offset);
        JSONObject root = callWithRetry(rpcUrl, "octra_tokenTransfersByAddress", p, 2);
        return extractResult(root);
    }

    /** {@code octra_tokensByAddress} — get list of tokens held by address. */
    public JSONArray getTokensByAddress(String rpcUrl, String address)
            throws Exception {
        JSONArray p = new JSONArray();
        p.put(address);
        JSONObject root = callWithRetry(rpcUrl, "octra_tokensByAddress", p, 2);
        if (root.has("result")) {
            Object r = root.get("result");
            if (r instanceof JSONArray) return (JSONArray) r;
        }
        return new JSONArray();
    }

    // ── Circles ───────────────────────────────────────────────────────────

    /** {@code circle_info} — fetch circle metadata */
    public JSONObject circleInfo(String rpcUrl, String circleId) throws Exception {
        JSONObject root = callWithRetry(rpcUrl, "circle_info",
                new JSONArray().put(circleId), 3);
        return extractResult(root);
    }

    /** {@code circle_asset} — fetch raw circle asset metadata & content */
    public JSONObject circleAsset(String rpcUrl, String circleId, String path) throws Exception {
        JSONObject root = callWithRetry(rpcUrl, "circle_asset",
                new JSONArray().put(circleId).put(path), 3);
        return extractResult(root);
    }

    /** {@code circle_asset_ciphertext} — fetch ciphertext of a sealed asset */
    public JSONObject circleAssetCiphertext(String rpcUrl, String circleId, String path) throws Exception {
        JSONObject root = callWithRetry(rpcUrl, "circle_asset_ciphertext",
                new JSONArray().put(circleId).put(path), 3);
        return extractResult(root);
    }

    /** {@code circle_asset_ciphertext_by_resource_key} — fetch ciphertext of a sealed asset by key */
    public JSONObject circleAssetCiphertextByKey(String rpcUrl, String circleId, String resourceKey) throws Exception {
        JSONObject root = callWithRetry(rpcUrl, "circle_asset_ciphertext_by_resource_key",
                new JSONArray().put(circleId).put(resourceKey), 3);
        return extractResult(root);
    }

    // ── Fee estimation ─────────────────────────────────────────────────────

    /**
     * {@code octra_recommendedFee} — fetch recommended fees via JSON-RPC 2.0.
     *
     * <p>Replaces the old REST {@code /api/fee} endpoint which only exists on
     * the webcli local server, not on the blockchain node itself.</p>
     *
     * @param rpcUrl base node URL
     * @return the fee structure (e.g. {@code {"standard":{"fast":"2000","minimum":"1000","recommended":"1000"}, ...}}),
     *         or {@code null} on failure
     */
    public JSONObject fetchFee(String rpcUrl) {
        try {
            JSONObject root = callWithRetry(rpcUrl, "octra_recommendedFee",
                    new JSONArray(), 2);
            return extractResult(root);
        } catch (Exception e) {
            Log.w(TAG, "fetchFee (octra_recommendedFee) failed: " + e.getMessage());
            return null;
        }
    }

    /**
     * Batch fee estimation for all operation types, mirroring webcli
     * {@code GET /api/fee} ({@code standard, encrypt, decrypt, stealth,
     * claim, deploy, call}). Each op is queried as
     * {@code octra_recommendedFee([op])}; failures fall back to
     * {@code {"minimum":"1000","recommended":"1000","fast":"2000"}}.
     *
     * @return fee map keyed by operation, never null
     */
    public JSONObject fetchFeeBatch(String rpcUrl) {
        String[] ops = {"standard", "encrypt", "decrypt", "stealth", "claim", "deploy", "call",
                "program_deploy", "program_exec", "multi_exec"};
        JSONObject fees = new JSONObject();
        for (String op : ops) {
            try {
                JSONArray p = new JSONArray().put(op);
                JSONObject root = callWithRetry(rpcUrl, "octra_recommendedFee", p, 2);
                JSONObject bucket = extractResult(root);
                if (bucket != null) {
                    fees.put(op, bucket);
                    continue;
                }
            } catch (Exception e) {
                Log.w(TAG, "fetchFeeBatch op " + op + " failed: " + e.getMessage());
            }
            try {
                JSONObject fb = new JSONObject();
                fb.put("minimum", "1000");
                fb.put("recommended", "1000");
                fb.put("fast", "2000");
                fees.put(op, fb);
            } catch (Exception ignored) {}
        }
        return fees;
    }

    /**
     * {@code octra_recommendedFee([op])} for a single op, or {@code null}
     * on failure. Used for ops outside the batch list (e.g. key_switch).
     */
    public JSONObject fetchFeeForOp(String rpcUrl, String op) {
        try {
            JSONArray p = new JSONArray().put(op);
            JSONObject root = callWithRetry(rpcUrl, "octra_recommendedFee", p, 2);
            return extractResult(root);
        } catch (Exception e) {
            Log.w(TAG, "fetchFeeForOp(" + op + ") failed: " + e.getMessage());
            return null;
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  INTERNAL HELPERS
    // ════════════════════════════════════════════════════════════════════════

    private JSONObject post(String url, JSONObject body) throws Exception {
        Request req = new Request.Builder()
                .url(url)
                .post(RequestBody.create(body.toString(), JSON_MEDIA))
                .build();
        try (Response resp = http.newCall(req).execute()) {
            if (resp.body() == null) {
                throw new IllegalStateException("Empty RPC response from " + url);
            }
            return new JSONObject(resp.body().string());
        }
    }

    /** Build the JSON-RPC endpoint URL from a base node URL. */
    static String buildRpcEndpoint(String rpcUrl) {
        String norm = UrlSecurityValidator.normalizeRpcUrl(rpcUrl);
        if (norm == null || norm.isEmpty()) norm = UrlSecurityValidator.DEFAULT_RPC;
        if (norm.endsWith("/rpc") || norm.endsWith("/rpc/")) return norm;
        return norm.endsWith("/") ? norm + "rpc" : norm + "/rpc";
    }

    /** Build the base URL (scheme + host + port, no path) for REST endpoints. */
    static String buildApiBase(String rpcUrl) {
        String norm = UrlSecurityValidator.normalizeRpcUrl(rpcUrl);
        if (norm == null || norm.isEmpty()) norm = UrlSecurityValidator.DEFAULT_RPC;
        // Strip /rpc suffix
        if (norm.endsWith("/rpc")) norm = norm.substring(0, norm.length() - 4);
        if (norm.endsWith("/"))    norm = norm.substring(0, norm.length() - 1);
        return norm;
    }

    /** Extract the {@code "result"} field (throws if missing). */
    private static JSONObject extractResult(JSONObject envelope) throws Exception {
        if (!envelope.has("result") || envelope.isNull("result")) {
            throwOnRpcError(envelope);
            throw new IllegalStateException("Invalid RPC response: missing 'result'");
        }
        Object r = envelope.get("result");
        if (r instanceof JSONObject) return (JSONObject) r;
        // Wrap scalar results
        JSONObject wrapper = new JSONObject();
        wrapper.put("value", r);
        return wrapper;
    }

    /** Extract the {@code "result"} field or return {@code null}. */
    private static JSONObject extractResultOrNull(JSONObject envelope) {
        try {
            if (!envelope.has("result") || envelope.isNull("result")) return null;
            Object r = envelope.get("result");
            if (r instanceof JSONObject) return (JSONObject) r;
            JSONObject wrapper = new JSONObject();
            wrapper.put("value", r);
            return wrapper;
        } catch (Exception e) {
            return null;
        }
    }

    /** If the envelope contains an {@code "error"} field, throw with its message. */
    private static void throwOnRpcError(JSONObject envelope) throws Exception {
        if (envelope.has("error") && !envelope.isNull("error")) {
            Object err = envelope.get("error");
            String msg;
            if (err instanceof JSONObject) {
                msg = ((JSONObject) err).optString("message", "RPC error");
            } else {
                msg = err.toString();
            }
            throw new IllegalStateException(msg);
        }
    }
}
