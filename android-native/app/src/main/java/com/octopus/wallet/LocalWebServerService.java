package com.octopus.wallet;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;

import androidx.core.app.NotificationCompat;
import androidx.core.content.ContextCompat;

import android.net.Uri;
import org.json.JSONArray;
import org.json.JSONObject;

import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import fi.iki.elonen.NanoHTTPD;

/**
 * Local HTTP server running on localhost:8420.
 *
 * <p>Implements a subset of the webcli REST API so the wallet can be accessed
 * from any browser on the same device (e.g. Chrome, Firefox).
 *
 * <p>Endpoints (all require {@code Authorization: Bearer <token>} header,
 * except {@code GET /api/status} which is public):
 * <ul>
 *   <li>{@code GET  /api/status}           — server health + version</li>
 *   <li>{@code GET  /api/wallet/info}       — address, RPC URL, nonce</li>
 *   <li>{@code GET  /api/balance}           — public + encrypted balance</li>
 *   <li>{@code GET  /api/history}           — paginated tx history</li>
 *   <li>{@code GET  /api/token-history}     — paginated token transfer history</li>
 *   <li>{@code POST /api/wallet/rename}     — rename wallet</li>
 *   <li>{@code GET  /api/keys/info}         — public key only (never private)</li>
 *   <li>{@code GET  /api/stealth/outputs}   — stealth outputs</li>
 * </ul>
 *
 * <p>The server runs as a foreground service so Android does not kill it while
 * the user has an active browser tab open.</p>
 */
public class LocalWebServerService extends Service {

    private static final String TAG = "LocalWebServerService";
    private static final String CHANNEL_ID = "local_web_server";
    private static final int NOTIF_ID = 7001;

    private OctraHttpServer httpServer;
    private final ExecutorService bgExecutor = Executors.newFixedThreadPool(2);

    // ── Service lifecycle ──────────────────────────────────────────────────

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        startForegroundCompat();
        if (httpServer == null || !httpServer.isAlive()) {
            startHttpServer();
        }
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        stopHttpServer();
        bgExecutor.shutdownNow();
    }

    // ── Static helpers ─────────────────────────────────────────────────────

    /** Start the service if enabled in settings. */
    public static void startIfEnabled(Context context) {
        if (LocalWebServerStore.isEnabled(context)) {
            Intent intent = new Intent(context, LocalWebServerService.class);
            ContextCompat.startForegroundService(context, intent);
        }
    }

    /** Stop the service unconditionally. */
    public static void stop(Context context) {
        context.stopService(new Intent(context, LocalWebServerService.class));
    }

    // ── HTTP Server ────────────────────────────────────────────────────────

    private void startHttpServer() {
        try {
            String authToken = LocalWebServerStore.getAuthToken(this);
            httpServer = new OctraHttpServer(
                    LocalWebServerStore.PORT,
                    authToken,
                    getApplicationContext(),
                    bgExecutor);
            httpServer.start(NanoHTTPD.SOCKET_READ_TIMEOUT, false);
            Log.i(TAG, "LocalWebServer started on port " + LocalWebServerStore.PORT);
        } catch (IOException e) {
            Log.e(TAG, "Failed to start LocalWebServer: " + e.getMessage());
            stopSelf();
        }
    }

    private void stopHttpServer() {
        if (httpServer != null) {
            httpServer.stop();
            httpServer = null;
        }
    }

    // ── Notification ───────────────────────────────────────────────────────

    private void startForegroundCompat() {
        Intent openIntent = new Intent(this, LocalWebServerSettingsActivity.class);
        openIntent.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent pi = PendingIntent.getActivity(
                this, 0, openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        Notification notif = new NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_network)
                .setContentTitle("Octra Local Web Server")
                .setContentText("Running on http://localhost:" + LocalWebServerStore.PORT)
                .setContentIntent(pi)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build();

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC);
        } else {
            startForeground(NOTIF_ID, notif);
        }
    }

    private void createNotificationChannel() {
        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                "Octra Local Web Server",
                NotificationManager.IMPORTANCE_LOW);
        channel.setDescription("Local HTTP API server for browser access");
        channel.setShowBadge(false);
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm != null) nm.createNotificationChannel(channel);
    }

    // ══════════════════════════════════════════════════════════════════════
    //  NanoHTTPD Server Implementation
    // ══════════════════════════════════════════════════════════════════════

    /* Package-visible for unit tests (pure helpers inside). */
    static final class OctraHttpServer extends NanoHTTPD {

        private final String authToken;
        private final Context appContext;
        private final ExecutorService executor;

        OctraHttpServer(int port, String authToken, Context context,
                        ExecutorService executor) throws IOException {
            super("127.0.0.1", port);
            this.authToken = authToken;
            this.appContext = context;
            this.executor = executor;
        }

        @Override
        public Response serve(IHTTPSession session) {
            try {
                String uri = session.getUri();
                Method method = session.getMethod();

                // CORS preflight
                if (Method.OPTIONS.equals(method)) {
                    return cors(newFixedLengthResponse(""));
                }

                // Validate Origin and Referer for security hardening
                if (uri.startsWith("/api/")) {
                    Map<String, String> headers = session.getHeaders();
                    String origin = headers.get("origin");
                    String referer = headers.get("referer");
                    if (origin != null && !origin.trim().isEmpty() && !isSafeHost(origin)) {
                        Log.w(TAG, "CORS origin blocked: " + origin);
                        return cors(jsonError(403, "Forbidden: Invalid Origin"));
                    }
                    if (referer != null && !referer.trim().isEmpty() && !isSafeHost(referer)) {
                        Log.w(TAG, "CORS referer blocked: " + referer);
                        return cors(jsonError(403, "Forbidden: Invalid Referer"));
                    }
                }

                // Dynamic Circle on-chain asset renderer
                if (uri.startsWith("/oct/")) {
                    return cors(serveCircleAssetDynamic(session, uri));
                }

                // Serve static assets for anything non-API
                if (!uri.startsWith("/api/")) {
                    return serveAsset(uri);
                }

                // Public: status endpoint
                if ("/api/status".equals(uri) && Method.GET.equals(method)) {
                    return cors(jsonOk(buildStatus()));
                }

                // Public: wallet status endpoint
                if ("/api/wallet/status".equals(uri) && Method.GET.equals(method)) {
                    return cors(jsonOk(buildStatus()));
                }

                // Public: wallet unlock
                if ("/api/wallet/unlock".equals(uri) && Method.POST.equals(method)) {
                    return cors(jsonOk(handleUnlock(session)));
                }

                // Public: contract view
                if ("/api/contract/view".equals(uri) && Method.GET.equals(method)) {
                    return cors(jsonOk(handleContractView(session)));
                }

                // Public: contract receipt
                if ("/api/contract/receipt".equals(uri) && Method.GET.equals(method)) {
                    return cors(jsonOk(handleContractReceipt(session)));
                }

                // Public: contract call (blocking approval)
                if ("/api/contract/call".equals(uri) && Method.POST.equals(method)) {
                    return cors(jsonOk(handleContractCall(session)));
                }

                // Public: batch fee estimation (webcli GET /api/fee parity).
                // No wallet needed — read-only node query with safe fallbacks.
                if ("/api/fee".equals(uri) && Method.GET.equals(method)) {
                    return cors(jsonOk(handleFee()));
                }

                // Legacy compat: old webcli UI posts to /key_switch (no /api prefix).
                // Requires auth like the /api/* equivalent below.
                if ("/key_switch".equals(uri) && Method.POST.equals(method)) {
                    if (!isAuthorized(session)) {
                        return cors(jsonError(401, "Unauthorized"));
                    }
                    return cors(jsonOk(handleKeySwitch()));
                }

                // Auth check for all other endpoints
                if (!isAuthorized(session)) {
                    return cors(jsonError(401, "Unauthorized"));
                }

                // Wallet info
                if (("/api/wallet/info".equals(uri) || "/api/wallet".equals(uri)) && Method.GET.equals(method)) {
                    return cors(jsonOk(handleWalletInfo()));
                }

                // Balance
                if ("/api/balance".equals(uri) && Method.GET.equals(method)) {
                    return cors(jsonOk(handleBalance(session)));
                }

                // History
                if ("/api/history".equals(uri) && Method.GET.equals(method)) {
                    return cors(jsonOk(handleHistory(session)));
                }

                // Token history
                if ("/api/token-history".equals(uri) && Method.GET.equals(method)) {
                    return cors(jsonOk(handleTokenHistory(session)));
                }

                // Keys info (public key only — never expose private key)
                if ("/api/keys/info".equals(uri) && Method.GET.equals(method)) {
                    return cors(jsonOk(handleKeysInfo()));
                }

                // Stealth outputs
                if ("/api/stealth/outputs".equals(uri) && Method.GET.equals(method)) {
                    return cors(jsonOk(handleStealthOutputs(session)));
                }

                // Wallet rename
                if ("/api/wallet/rename".equals(uri) && Method.POST.equals(method)) {
                    return cors(jsonOk(handleRename(session)));
                }

                // Wallet list
                if ("/api/wallets".equals(uri) && Method.GET.equals(method)) {
                    return cors(jsonOk(handleWalletList()));
                }

                // GET Circle APIs
                if ("/api/circle/info".equals(uri) && Method.GET.equals(method)) {
                    return cors(jsonOk(handleCircleInfo(session)));
                }
                if ("/api/circle/asset".equals(uri) && Method.GET.equals(method)) {
                    return cors(jsonOk(handleCircleAsset(session)));
                }
                if ("/api/circle/asset_ciphertext".equals(uri) && Method.GET.equals(method)) {
                    return cors(jsonOk(handleCircleAssetCiphertext(session)));
                }
                if ("/api/circle/asset_ciphertext_by_key".equals(uri) && Method.GET.equals(method)) {
                    return cors(jsonOk(handleCircleAssetCiphertextByKey(session)));
                }

                // POST Circle, FHE & Bridge APIs
                if ("/api/circle/deploy".equals(uri) && Method.POST.equals(method)) {
                    return cors(jsonOk(handleCircleDeploy(session)));
                }
                if ("/api/circle/asset_encrypted".equals(uri) && Method.POST.equals(method)) {
                    return cors(jsonOk(handleCircleAssetEncrypted(session)));
                }
                if ("/api/fhe/encrypt".equals(uri) && Method.POST.equals(method)) {
                    return cors(jsonOk(handleFheEncrypt(session)));
                }
                if ("/api/fhe/decrypt".equals(uri) && Method.POST.equals(method)) {
                    return cors(jsonOk(handleFheDecrypt(session)));
                }
                if ("/api/bridge/signer".equals(uri) && Method.POST.equals(method)) {
                    return cors(handleBridgeSigner(session));
                }

                // PVAC key rotation (webcli POST /api/key_switch parity)
                if ("/api/key_switch".equals(uri) && Method.POST.equals(method)) {
                    return cors(jsonOk(handleKeySwitch()));
                }

                // Fast token listing (webcli GET /api/tokens parity)
                if ("/api/tokens".equals(uri) && Method.GET.equals(method)) {
                    return cors(jsonOk(handleTokens()));
                }

                // 404
                return cors(jsonError(404, "Not found"));

            } catch (BadRequestException e) {
                return cors(jsonError(400, e.getMessage()));
            } catch (Exception e) {
                Log.e("LocalWebServer", "Error handling request: " + e.getMessage());
                return cors(jsonError(500, "Internal server error: " + safeMessage(e)));
            }
        }

        /**
         * Malformed client input (bad JSON body, invalid params). Mapped to
         * HTTP 400 by the router above — distinct from 500 internal errors.
         */
        static final class BadRequestException extends Exception {
            BadRequestException(String message) {
                super(message);
            }
        }

        // ── Endpoint handlers ────────────────────────────────────────────

        private JSONObject buildStatus() throws Exception {
            JSONObject j = new JSONObject();
            j.put("status", "running");
            j.put("port", LocalWebServerStore.PORT);
            j.put("version", "1.0");
            boolean loaded = OctraNative.getInstance().isWalletLoaded();
            j.put("loaded", loaded);
            j.put("wallet_loaded", loaded);
            j.put("has_encrypted", OctraNative.getInstance().hasEncryptedWallet());
            return j;
        }

        private JSONObject handleWalletInfo() throws Exception {
            String raw = OctraNative.getInstance().getWalletInfo();
            if (raw == null || raw.isEmpty()) {
                JSONObject err = new JSONObject();
                err.put("error", "Wallet not loaded");
                return err;
            }
            JSONObject info = new JSONObject(raw);
            // Strip private key fields for safety
            info.remove("priv");
            info.remove("sk");
            info.remove("private_key");
            info.remove("master_seed");
            info.remove("mnemonic");
            return info;
        }

        private JSONObject handleBalance(IHTTPSession session) throws Exception {
            JSONObject info = safeWalletInfo();
            if (info.has("error")) return info;

            String rpcUrl = info.optString("rpc_url", UrlSecurityValidator.DEFAULT_RPC);
            String address = info.optString("address", "");

            WalletRepository repo = new WalletRepository(appContext);
            WalletRepository.Result<WalletRepository.BalanceSummary> result =
                    repo.fetchBalance(rpcUrl, address);

            JSONObject out = new JSONObject();
            if (result.isSuccess()) {
                WalletRepository.BalanceSummary s = result.getValue();
                out.put("public_raw", s.publicRaw);
                out.put("encrypted_raw", s.encryptedRaw);
                out.put("total_raw", s.totalRaw);
                out.put("public_oct", WalletRepository.formatOct(s.publicRaw));
                out.put("encrypted_oct", WalletRepository.formatOct(s.encryptedRaw));
                out.put("total_oct", WalletRepository.formatOct(s.totalRaw));
                out.put("nonce", s.nonce);
            } else {
                out.put("error", result.getError());
            }
            return out;
        }

        private JSONObject handleHistory(IHTTPSession session) throws Exception {
            Map<String, List<String>> params = session.getParameters();
            int limit = parseBoundedInt(params, "limit", 20, 1, 200);
            int offset = parseBoundedInt(params, "offset", 0, 0, 1000000);

            JSONObject info = safeWalletInfo();
            if (info.has("error")) return info;

            String rpcUrl = info.optString("rpc_url", UrlSecurityValidator.DEFAULT_RPC);
            String address = info.optString("address", "");

            WalletRepository repo = new WalletRepository(appContext);
            List<JSONObject> txs = repo.fetchHistory(rpcUrl, address, limit, offset);

            JSONArray arr = new JSONArray();
            for (JSONObject tx : txs) arr.put(tx);

            JSONObject out = new JSONObject();
            out.put("transactions", arr);
            out.put("count", arr.length());
            out.put("limit", limit);
            out.put("offset", offset);
            return out;
        }

        private JSONObject handleTokenHistory(IHTTPSession session) throws Exception {
            Map<String, List<String>> params = session.getParameters();
            int limit = parseBoundedInt(params, "limit", 20, 1, 200);
            int offset = parseBoundedInt(params, "offset", 0, 0, 1000000);

            JSONObject info = safeWalletInfo();
            if (info.has("error")) return info;

            String rpcUrl = info.optString("rpc_url", UrlSecurityValidator.DEFAULT_RPC);
            String address = info.optString("address", "");

            WalletRepository repo = new WalletRepository(appContext);
            List<JSONObject> txs = repo.fetchTokenHistory(rpcUrl, address, limit, offset);

            JSONArray arr = new JSONArray();
            for (JSONObject tx : txs) arr.put(tx);

            JSONObject out = new JSONObject();
            out.put("transfers", arr);
            out.put("count", arr.length());
            out.put("limit", limit);
            out.put("offset", offset);
            return out;
        }

        private JSONObject handleKeysInfo() throws Exception {
            JSONObject out = new JSONObject();
            try {
                String pubB64 = OctraNative.getInstance().getPublicKeyB64();
                JSONObject info = safeWalletInfo();
                out.put("address", info.optString("address", ""));
                out.put("public_key_b64", pubB64);
                out.put("note", "Private key is never exposed via API");
            } catch (Exception e) {
                out.put("error", safeMessage(e));
            }
            return out;
        }

        private JSONObject handleStealthOutputs(IHTTPSession session) throws Exception {
            Map<String, List<String>> params = session.getParameters();
            int fromEpoch = parseBoundedInt(params, "from_epoch", 0, 0, Integer.MAX_VALUE);

            JSONObject info = safeWalletInfo();
            if (info.has("error")) return info;

            String rpcUrl = info.optString("rpc_url", UrlSecurityValidator.DEFAULT_RPC);

            WalletRepository repo = new WalletRepository(appContext);
            JSONArray outputs = repo.fetchStealthOutputs(rpcUrl, fromEpoch);

            JSONObject out = new JSONObject();
            out.put("outputs", outputs);
            out.put("count", outputs.length());
            return out;
        }

        private JSONObject handleRename(IHTTPSession session) throws Exception {
            // Read POST body
            Map<String, String> body = new HashMap<>();
            try {
                session.parseBody(body);
            } catch (Exception ignored) {}

            String postBody = body.get("postData");
            if (postBody == null || postBody.isEmpty()) {
                return errorJson("Missing request body");
            }

            JSONObject req = new JSONObject(postBody);
            String newName = req.optString("name", "").trim();
            if (newName.isEmpty()) {
                return errorJson("name is required");
            }

            String currentId = WalletProfileStore.getSelectedWalletId(appContext);
            boolean ok = WalletProfileStore.renameWallet(appContext, currentId, newName);
            JSONObject out = new JSONObject();
            if (ok) {
                out.put("success", true);
                out.put("new_name", newName);
            } else {
                out.put("success", false);
                out.put("error", "Rename failed — name may already exist");
            }
            return out;
        }

        private JSONObject handleWalletList() throws Exception {
            List<String> ids = WalletProfileStore.getWalletIds(appContext);
            String selected = WalletProfileStore.getSelectedWalletId(appContext);
            JSONArray arr = new JSONArray();
            for (String id : ids) arr.put(id);
            JSONObject out = new JSONObject();
            out.put("wallets", arr);
            out.put("selected", selected);
            return out;
        }

        // ── Auth ──────────────────────────────────────────────────────────

        private boolean isAuthorized(IHTTPSession session) {
            Map<String, String> headers = session.getHeaders();
            return isAuthorizedToken(authToken, headers.get("authorization"));
        }

        /**
         * Bearer-token check. Fail-closed: a missing/empty configured token
         * denies everything (an open server on misconfiguration is never
         * acceptable). Comparison is constant-time. Package-visible for tests.
         */
        static boolean isAuthorizedToken(String configuredToken, String authHeader) {
            if (configuredToken == null || configuredToken.isEmpty()) {
                Log.w(TAG, "Unauthorized request: server has no auth token configured");
                return false;
            }
            if (authHeader == null || !authHeader.startsWith("Bearer ")) {
                Log.w(TAG, "Unauthorized request: missing or invalid Bearer token");
                return false;
            }
            String presented = authHeader.substring(7).trim();
            if (presented.isEmpty()) {
                Log.w(TAG, "Unauthorized request: empty Bearer token");
                return false;
            }
            byte[] a;
            byte[] b;
            try {
                a = configuredToken.getBytes("UTF-8");
                b = presented.getBytes("UTF-8");
            } catch (java.io.UnsupportedEncodingException impossible) {
                return false;
            }
            boolean ok = java.security.MessageDigest.isEqual(a, b);
            if (!ok) {
                Log.w(TAG, "Unauthorized request: token mismatch");
            }
            return ok;
        }

        private boolean isSafeHost(String urlStr) {
            try {
                if (urlStr.startsWith("chrome-extension://")) {
                    return true;
                }
                Uri uri = Uri.parse(urlStr);
                String host = uri.getHost();
                if (host == null) return false;
                return "localhost".equalsIgnoreCase(host) || "127.0.0.1".equals(host);
            } catch (Exception e) {
                return false;
            }
        }

        // ── Response helpers ──────────────────────────────────────────────

        private static Response jsonOk(JSONObject body) {
            String s = body == null ? "{}" : body.toString();
            return newFixedLengthResponse(Response.Status.OK, "application/json", s);
        }

        private static Response jsonError(int code, String message) {
            try {
                JSONObject err = new JSONObject();
                err.put("error", message);
                Response.IStatus status = Response.Status.lookup(code);
                if (status == null) status = Response.Status.INTERNAL_ERROR;
                return newFixedLengthResponse(status, "application/json", err.toString());
            } catch (Exception e) {
                return newFixedLengthResponse(Response.Status.INTERNAL_ERROR,
                        "application/json", "{\"error\":\"internal error\"}");
            }
        }

        private static Response cors(Response r) {
            r.addHeader("Access-Control-Allow-Origin", "*");
            r.addHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
            r.addHeader("Access-Control-Allow-Headers",
                    "Authorization, Content-Type");
            return r;
        }

        // ── Utility ───────────────────────────────────────────────────────

        private JSONObject safeWalletInfo() throws Exception {
            try {
                String raw = OctraNative.getInstance().getWalletInfo();
                if (raw == null || raw.isEmpty()) {
                    return errorJson("Wallet not loaded");
                }
                JSONObject info = new JSONObject(raw);
                if (info.has("error")) return info;
                // Strip sensitive fields
                info.remove("priv");
                info.remove("sk");
                info.remove("private_key");
                info.remove("master_seed");
                info.remove("mnemonic");
                return info;
            } catch (Exception e) {
                return errorJson("Failed to load wallet: " + safeMessage(e));
            }
        }

        private static JSONObject errorJson(String msg) throws Exception {
            JSONObject j = new JSONObject();
            j.put("error", msg);
            return j;
        }

        private static int parseIntParam(Map<String, List<String>> params,
                                         String key, int defaultVal) {
            List<String> vals = params.get(key);
            if (vals == null || vals.isEmpty()) return defaultVal;
            try {
                return Integer.parseInt(vals.get(0));
            } catch (NumberFormatException ignored) {
                return defaultVal;
            }
        }

        /**
         * Bounded query integer: garbage falls back to {@code defaultVal},
         * out-of-range values clamp into {@code [min, max]} (prevents absurd
         * limit/offset/epoch values from reaching the node). Package-visible
         * for tests.
         */
        static int parseBoundedInt(Map<String, List<String>> params,
                                   String key, int defaultVal, int min, int max) {
            int v = parseIntParam(params, key, defaultVal);
            if (v < min) return min;
            if (v > max) return max;
            return v;
        }

        /**
         * Require a non-blank value, else throw a 400-mapped error naming
         * the missing field. Package-visible for tests.
         */
        static String requireNonEmpty(String value, String fieldName) throws BadRequestException {
            if (value == null || value.trim().isEmpty()) {
                throw new BadRequestException(fieldName + " is required");
            }
            return value.trim();
        }

        /** Amount/OU strings must be non-negative integers (microcoins). */
        static String requireUintString(String value, String fieldName) throws BadRequestException {
            String v = requireNonEmpty(value, fieldName);
            if (!v.matches("\\d+")) {
                throw new BadRequestException(fieldName + " must be a non-negative integer (got '" + value + "')");
            }
            return v;
        }

        private static String safeMessage(Exception e) {
            if (e == null) return "unknown error";
            String msg = e.getMessage();
            return msg == null ? e.getClass().getSimpleName() : msg;
        }

        // ── New Helpers for WebCLI and Contract Support ────────────────────

        private Response serveAsset(String uri) {
            if (uri.startsWith("/")) {
                uri = uri.substring(1);
            }
            if (uri.isEmpty()) {
                uri = "swap.html";
            }
            if (uri.contains("..")) {
                return cors(jsonError(403, "Forbidden"));
            }
            try {
                String assetPath = "webcli/" + uri;
                java.io.InputStream is = appContext.getAssets().open(assetPath);
                String mimeType = getMimeType(uri);
                return cors(newChunkedResponse(Response.Status.OK, mimeType, is));
            } catch (IOException e) {
                try {
                    String assetPath = "webcli/" + uri + ".html";
                    java.io.InputStream is = appContext.getAssets().open(assetPath);
                    return cors(newChunkedResponse(Response.Status.OK, "text/html", is));
                } catch (IOException e2) {
                    return cors(jsonError(404, "File not found: " + uri));
                }
            }
        }

        /** Static so JVM tests can assert MIME mapping without sockets. */
        static String getMimeType(String uri) {
            if (uri == null) return "application/octet-stream";
            if (uri.endsWith(".html") || uri.endsWith(".htm")) return "text/html";
            if (uri.endsWith(".css")) return "text/css";
            // .mjs must be a script type or browsers refuse ES module imports.
            if (uri.endsWith(".mjs")) return "application/javascript";
            if (uri.endsWith(".js")) return "application/javascript";
            if (uri.endsWith(".png")) return "image/png";
            if (uri.endsWith(".jpg") || uri.endsWith(".jpeg")) return "image/jpeg";
            if (uri.endsWith(".gif")) return "image/gif";
            if (uri.endsWith(".svg")) return "image/svg+xml";
            if (uri.endsWith(".json")) return "application/json";
            return "application/octet-stream";
        }

        private JSONObject handleUnlock(IHTTPSession session) throws Exception {
            Map<String, String> body = new HashMap<>();
            try {
                session.parseBody(body);
            } catch (Exception ignored) {}

            String postBody = body.get("postData");
            if (postBody == null || postBody.isEmpty()) {
                return errorJson("Missing request body");
            }

            JSONObject req;
            try {
                req = new JSONObject(postBody);
            } catch (org.json.JSONException e) {
                return errorJson("Request body must be valid JSON");
            }
            String pin = req.optString("pin", "").trim();
            if (pin.isEmpty()) {
                return errorJson("pin is required");
            }

            String result = OctraNative.getInstance().unlockWallet(pin);
            JSONObject json = new JSONObject(result);
            if (json.has("error")) {
                return errorJson(json.getString("error"));
            }

            PinStore.setDefaultPin(appContext, pin);
            String address = json.getString("address");
            String walletId = WalletProfileStore.getSelectedWalletId(appContext);
            WalletAddressStore.putAddress(appContext.getApplicationContext(), walletId, address);

            JSONObject out = new JSONObject();
            out.put("success", true);
            out.put("address", address);
            return out;
        }

        private JSONObject handleContractView(IHTTPSession session) throws Exception {
            Map<String, List<String>> params = session.getParameters();
            List<String> addrs = params.get("address");
            List<String> methods = params.get("method");
            List<String> pList = params.get("params");

            String contractAddr = (addrs != null && !addrs.isEmpty()) ? addrs.get(0) : "";
            String method = (methods != null && !methods.isEmpty()) ? methods.get(0) : "";
            String paramsStr = (pList != null && !pList.isEmpty()) ? pList.get(0) : "[]";

            if (contractAddr.isEmpty() || method.isEmpty()) {
                return errorJson("Missing address or method");
            }

            JSONObject info = safeWalletInfo();
            String rpcUrl = info.optString("rpc_url", UrlSecurityValidator.DEFAULT_RPC);
            String walletAddr = info.optString("address", "");

            JSONArray args;
            try {
                args = new JSONArray(paramsStr);
            } catch (org.json.JSONException e) {
                return errorJson("params must be a valid JSON array");
            }
            JSONObject result = OctraRpcClient.getInstance().contractView(rpcUrl, contractAddr, method, args, walletAddr);
            if (result == null) {
                return errorJson("Contract view call returned null");
            }

            JSONObject out = new JSONObject();
            if (result.has("value")) {
                out.put("result", result.get("value"));
                out.put("value", result.get("value"));
            } else if (result.has("result")) {
                out.put("result", result.get("result"));
                out.put("value", result.get("result"));
            } else {
                out.put("result", result);
                out.put("value", result);
            }
            return out;
        }

        private JSONObject handleContractReceipt(IHTTPSession session) throws Exception {
            Map<String, List<String>> params = session.getParameters();
            List<String> hashes = params.get("hash");
            if (hashes == null || hashes.isEmpty()) {
                return errorJson("Missing transaction hash");
            }
            String txHash = requireNonEmpty(hashes.get(0), "hash");

            JSONObject info = safeWalletInfo();
            String rpcUrl = info.optString("rpc_url", UrlSecurityValidator.DEFAULT_RPC);

            JSONObject result = OctraRpcClient.getInstance().contractReceipt(rpcUrl, txHash);
            if (result == null) {
                return errorJson("Receipt not found");
            }

            boolean success = result.optBoolean("success", false)
                    || "1".equals(result.optString("status"))
                    || result.optInt("status", 0) == 1
                    || "success".equalsIgnoreCase(result.optString("status"));

            JSONObject out = new JSONObject();
            out.put("success", success);
            if (result.has("error")) {
                out.put("error", result.optString("error"));
            } else if (!success && result.has("revert_reason")) {
                out.put("error", result.optString("revert_reason"));
            } else if (!success && result.has("message")) {
                out.put("error", result.optString("message"));
            }

            JSONArray names = result.names();
            if (names != null) {
                for (int i = 0; i < names.length(); i++) {
                    String name = names.getString(i);
                    if (!out.has(name)) {
                        out.put(name, result.get(name));
                    }
                }
            }
            return out;
        }

        private JSONObject handleContractCall(IHTTPSession session) throws Exception {
            Map<String, String> body = new HashMap<>();
            try {
                session.parseBody(body);
            } catch (Exception ignored) {}

            String postBody = body.get("postData");
            if (postBody == null || postBody.isEmpty()) {
                return errorJson("Missing request body");
            }

            JSONObject req;
            try {
                req = new JSONObject(postBody);
            } catch (org.json.JSONException e) {
                return errorJson("Request body must be valid JSON");
            }
            String contractAddr = req.optString("address", "").trim();
            String method = req.optString("method", "").trim();
            JSONArray params = req.optJSONArray("params");
            if (req.has("params") && params == null) {
                return errorJson("params must be a JSON array");
            }
            String paramsStr = params != null ? params.toString() : "[]";
            String amount;
            String ou;
            try {
                amount = requireUintString(req.optString("amount", "0"), "amount");
                ou = requireUintString(req.optString("ou", "1000"), "ou");
            } catch (BadRequestException e) {
                return errorJson(e.getMessage());
            }

            if (contractAddr.isEmpty() || method.isEmpty()) {
                return errorJson("Missing address or method");
            }

            String requestId = "req_" + java.util.UUID.randomUUID().toString();
            TxRequestManager.TxRequest txReq = TxRequestManager.createRequest(requestId);

            Uri.Builder uriBuilder = Uri.parse("octra-wallet://contract-call").buildUpon();
            uriBuilder.appendQueryParameter("address", contractAddr);
            uriBuilder.appendQueryParameter("method", method);
            uriBuilder.appendQueryParameter("params", paramsStr);
            uriBuilder.appendQueryParameter("amount", amount);
            uriBuilder.appendQueryParameter("ou", ou);
            uriBuilder.appendQueryParameter("callback", "octra-local://callback");
            uriBuilder.appendQueryParameter("requestId", requestId);

            Intent intent = new Intent(Intent.ACTION_VIEW, uriBuilder.build());
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            try {
                appContext.startActivity(intent);
            } catch (android.content.ActivityNotFoundException e) {
                Log.e(TAG, "Deep link activity not found: " + e.getMessage());
                TxRequestManager.removeRequest(requestId);
                return errorJson("Activity not found for deep link: " + e.getMessage());
            }

            try {
                boolean completed = txReq.latch.await(5, java.util.concurrent.TimeUnit.MINUTES);
                if (!completed) {
                    TxRequestManager.removeRequest(requestId);
                    return errorJson("Transaction confirmation timed out after 5 minutes");
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                TxRequestManager.removeRequest(requestId);
                return errorJson("Transaction confirmation interrupted");
            }

            TxRequestManager.removeRequest(requestId);

            JSONObject out = new JSONObject();
            if (txReq.approved) {
                out.put("success", true);
                out.put("tx_hash", txReq.txHash);
            } else {
                out.put("success", false);
                out.put("error", txReq.error != null ? txReq.error : "Transaction rejected by user");
            }
            return out;
        }

        private String getQueryParam(IHTTPSession session, String key) {
            Map<String, List<String>> params = session.getParameters();
            if (params == null) return "";
            List<String> list = params.get(key);
            if (list == null || list.isEmpty()) return "";
            return list.get(0);
        }

        private Response serveCircleAssetDynamic(IHTTPSession session, String uri) {
            if (!uri.startsWith("/oct/")) {
                return jsonError(400, "Invalid circle path");
            }
            String sub = uri.substring(5);
            if (sub.isEmpty()) {
                return jsonError(400, "circle_id required");
            }
            int idx = sub.indexOf('/');
            String circleId;
            String path;
            if (idx == -1) {
                circleId = sub;
                path = "/index.html";
            } else {
                circleId = sub.substring(0, idx);
                path = sub.substring(idx);
                if (path.isEmpty() || "/".equals(path)) {
                    path = "/index.html";
                }
            }

            try {
                JSONObject info = safeWalletInfo();
                String rpcUrl = info.optString("rpc_url", UrlSecurityValidator.DEFAULT_RPC);
                JSONObject asset = OctraRpcClient.getInstance().circleAsset(rpcUrl, circleId, path);
                if (asset == null || asset.has("error")) {
                    String err = asset != null ? asset.optString("error", "Not found") : "Not found";
                    return jsonError(404, "Circle asset error: " + err);
                }
                String contentType = asset.optString("content_type", "application/octet-stream");
                String bodyB64 = asset.optString("body_b64", "");
                byte[] raw = OctraNative.getInstance().base64Decode(bodyB64);
                if (raw == null) {
                    raw = new byte[0];
                }
                Response r = newFixedLengthResponse(Response.Status.OK, contentType, new java.io.ByteArrayInputStream(raw), raw.length);
                r.addHeader("Cache-Control", "no-store");
                r.addHeader("X-Content-Type-Options", "nosniff");
                return r;
            } catch (Exception e) {
                Log.e("LocalWebServer", "Error in serveCircleAssetDynamic: " + e.getMessage());
                return jsonError(500, "Error rendering circle asset: " + safeMessage(e));
            }
        }

        private JSONObject handleCircleInfo(IHTTPSession session) throws Exception {
            String circleId = getQueryParam(session, "circle_id");
            if (circleId.isEmpty()) {
                return errorJson("circle_id required");
            }
            JSONObject info = safeWalletInfo();
            if (info.has("error")) return info;
            String rpcUrl = info.optString("rpc_url", UrlSecurityValidator.DEFAULT_RPC);
            try {
                JSONObject res = OctraRpcClient.getInstance().circleInfo(rpcUrl, circleId);
                if (res == null) return errorJson("Failed to query circle_info");
                return res;
            } catch (Exception e) {
                return errorJson("Failed to fetch circle info: " + safeMessage(e));
            }
        }

        private JSONObject handleCircleAsset(IHTTPSession session) throws Exception {
            String circleId = getQueryParam(session, "circle_id");
            String path = getQueryParam(session, "path");
            if (circleId.isEmpty() || path.isEmpty()) {
                return errorJson("circle_id and path required");
            }
            if (path.contains("..")) {
                return errorJson("Path traversal not allowed");
            }
            JSONObject info = safeWalletInfo();
            if (info.has("error")) return info;
            String rpcUrl = info.optString("rpc_url", UrlSecurityValidator.DEFAULT_RPC);
            try {
                JSONObject res = OctraRpcClient.getInstance().circleAsset(rpcUrl, circleId, path);
                if (res == null) return errorJson("Failed to query circle_asset");
                return res;
            } catch (Exception e) {
                return errorJson("Failed to fetch circle asset: " + safeMessage(e));
            }
        }

        private JSONObject handleCircleAssetCiphertext(IHTTPSession session) throws Exception {
            String circleId = getQueryParam(session, "circle_id");
            String path = getQueryParam(session, "path");
            if (circleId.isEmpty() || path.isEmpty()) {
                return errorJson("circle_id and path required");
            }
            if (path.contains("..")) {
                return errorJson("Path traversal not allowed");
            }
            JSONObject info = safeWalletInfo();
            if (info.has("error")) return info;
            String rpcUrl = info.optString("rpc_url", UrlSecurityValidator.DEFAULT_RPC);
            try {
                JSONObject res = OctraRpcClient.getInstance().circleAssetCiphertext(rpcUrl, circleId, path);
                if (res == null) return errorJson("Failed to query circle_asset_ciphertext");
                return res;
            } catch (Exception e) {
                return errorJson("Failed to fetch circle asset ciphertext: " + safeMessage(e));
            }
        }

        private JSONObject handleCircleAssetCiphertextByKey(IHTTPSession session) throws Exception {
            String circleId = getQueryParam(session, "circle_id");
            String resourceKey = getQueryParam(session, "resource_key");
            if (circleId.isEmpty() || resourceKey.isEmpty()) {
                return errorJson("circle_id and resource_key required");
            }
            JSONObject info = safeWalletInfo();
            if (info.has("error")) return info;
            String rpcUrl = info.optString("rpc_url", UrlSecurityValidator.DEFAULT_RPC);
            try {
                JSONObject res = OctraRpcClient.getInstance().circleAssetCiphertextByKey(rpcUrl, circleId, resourceKey);
                if (res == null) return errorJson("Failed to query circle_asset_ciphertext_by_key");
                return res;
            } catch (Exception e) {
                return errorJson("Failed to fetch circle asset ciphertext by key: " + safeMessage(e));
            }
        }

        private static JSONObject parsePostBody(IHTTPSession session) throws Exception {
            Map<String, String> body = new HashMap<>();
            try {
                session.parseBody(body);
            } catch (Exception e) {
                throw new BadRequestException("Malformed request body: " + safeMessage(e));
            }
            String postBody = body.get("postData");
            if (postBody == null || postBody.isEmpty()) {
                return new JSONObject();
            }
            try {
                return new JSONObject(postBody);
            } catch (org.json.JSONException e) {
                throw new BadRequestException("Request body must be valid JSON");
            }
        }

        private JSONObject handleCircleDeploy(IHTTPSession session) throws Exception {
            JSONObject body = parsePostBody(session);
            String circleId = body.optString("circle_id", "").trim();
            if (circleId.isEmpty()) {
                return errorJson("circle_id required");
            }
            String runtime = body.optString("runtime", "octb");
            String privacyClass = body.optString("privacy_class", "sealed");
            String browserMode = body.optString("browser_mode", "native_sealed");
            String resourceMode = body.optString("resource_mode", "sealed_read");
            String codeB64 = body.optString("code_b64", "");
            String policyHash = body.optString("policy_hash", "");
            String membersRoot = body.optString("members_root", "");
            String exportPolicy = body.optString("export_policy", "");
            String ou = body.optString("ou", "200000").trim();

            JSONObject limits = body.optJSONObject("limits");
            if (limits == null) limits = new JSONObject();

            JSONObject payloadLimits = new JSONObject();
            payloadLimits.put("max_stable_bytes", getLimitString(limits, "max_stable_bytes", "33554432"));
            payloadLimits.put("max_assets_bytes", getLimitString(limits, "max_assets_bytes", "33554432"));
            payloadLimits.put("max_inline_value", getLimitString(limits, "max_inline_value", "65536"));
            payloadLimits.put("max_wasm_bytes", getLimitString(limits, "max_wasm_bytes", "33554432"));

            JSONObject payload = new JSONObject();
            payload.put("runtime", runtime);
            payload.put("privacy_class", privacyClass);
            payload.put("browser_mode", browserMode);
            payload.put("resource_mode", resourceMode);
            payload.put("limits", payloadLimits);

            if (!codeB64.isEmpty()) payload.put("code_b64", codeB64);
            if (!policyHash.isEmpty()) payload.put("policy_hash", policyHash);
            if (!membersRoot.isEmpty()) payload.put("members_root", membersRoot);
            if (!exportPolicy.isEmpty()) payload.put("export_policy", exportPolicy);

            JSONObject info = safeWalletInfo();
            if (info.has("error")) return info;
            String rpcUrl = info.optString("rpc_url", UrlSecurityValidator.DEFAULT_RPC);
            String address = info.optString("address", "");

            WalletRepository repo = new WalletRepository(appContext);
            WalletRepository.Result<WalletRepository.BalanceSummary> result = repo.fetchBalance(rpcUrl, address);
            if (!result.isSuccess()) {
                return errorJson("Failed to fetch balance/nonce: " + result.getError());
            }
            int nextNonce = result.getValue().nonce + 1;

            String message = payload.toString();
            String signedTxStr = OctraNative.getInstance().signGeneralTransaction(
                    circleId, "0", nextNonce, ou, "deploy_circle", message, ""
            );

            if (signedTxStr == null || signedTxStr.isEmpty()) {
                return errorJson("Failed to sign general transaction");
            }
            JSONObject signedTx = new JSONObject(signedTxStr);
            if (signedTx.has("error")) {
                return signedTx;
            }

            JSONObject submitRes = OctraRpcClient.getInstance().submitTx(rpcUrl, signedTx);
            if (submitRes == null) {
                return errorJson("Submit transaction returned null");
            }
            if (!submitRes.has("error")) {
                submitRes.put("circle_id", circleId);
            }
            return submitRes;
        }

        private static String getLimitString(JSONObject limits, String key, String fallback) {
            if (limits == null || !limits.has(key)) return fallback;
            Object val = limits.opt(key);
            if (val == null) return fallback;
            return val.toString();
        }

        private JSONObject handleCircleAssetEncrypted(IHTTPSession session) throws Exception {
            JSONObject body = parsePostBody(session);
            String circleId = body.optString("circle_id", "").trim();
            String path = body.optString("path", "").trim();
            String contentType = body.optString("content_type", "").trim();
            String ciphertextB64 = body.optString("ciphertext_b64", "").trim();
            String keyId = body.optString("key_id", "").trim();
            String plaintextHash = body.optString("plaintext_hash", "").trim();
            String encoding = body.optString("encoding", "").trim();
            String paddingClass = body.optString("padding_class", "").trim();
            String ou = body.optString("ou", "5000").trim();

            if (circleId.isEmpty() || path.isEmpty() || contentType.isEmpty() ||
                ciphertextB64.isEmpty() || keyId.isEmpty() || plaintextHash.isEmpty()) {
                return errorJson("circle_id, path, content_type, ciphertext_b64, key_id, and plaintext_hash required");
            }

            JSONObject payload = new JSONObject();
            payload.put("path", path);
            payload.put("content_type", contentType);
            payload.put("key_id", keyId);
            payload.put("plaintext_hash", plaintextHash);
            if (!encoding.isEmpty()) payload.put("encoding", encoding);
            if (!paddingClass.isEmpty()) payload.put("padding_class", paddingClass);

            JSONObject info = safeWalletInfo();
            if (info.has("error")) return info;
            String rpcUrl = info.optString("rpc_url", UrlSecurityValidator.DEFAULT_RPC);
            String address = info.optString("address", "");

            WalletRepository repo = new WalletRepository(appContext);
            WalletRepository.Result<WalletRepository.BalanceSummary> result = repo.fetchBalance(rpcUrl, address);
            if (!result.isSuccess()) {
                return errorJson("Failed to fetch balance/nonce: " + result.getError());
            }
            int nextNonce = result.getValue().nonce + 1;

            String message = payload.toString();
            String signedTxStr = OctraNative.getInstance().signGeneralTransaction(
                    circleId, "0", nextNonce, ou, "circle_asset_put_encrypted", message, ciphertextB64
            );

            if (signedTxStr == null || signedTxStr.isEmpty()) {
                return errorJson("Failed to sign general transaction");
            }
            JSONObject signedTx = new JSONObject(signedTxStr);
            if (signedTx.has("error")) {
                return signedTx;
            }

            JSONObject submitRes = OctraRpcClient.getInstance().submitTx(rpcUrl, signedTx);
            if (submitRes == null) {
                return errorJson("Submit transaction returned null");
            }
            return submitRes;
        }

        private JSONObject handleFee() throws Exception {
            String rpcUrl = UrlSecurityValidator.DEFAULT_RPC;
            try {
                JSONObject info = safeWalletInfo();
                if (!info.has("error")) {
                    rpcUrl = info.optString("rpc_url", rpcUrl);
                }
            } catch (Exception ignored) {}
            WalletRepository repo = new WalletRepository(appContext);
            return repo.fetchFeeBatch(rpcUrl);
        }

        private JSONObject handleKeySwitch() throws Exception {
            JSONObject info = safeWalletInfo();
            if (info.has("error")) return info;
            String rpcUrl = info.optString("rpc_url", UrlSecurityValidator.DEFAULT_RPC);
            String address = info.optString("address", "");
            if (address.isEmpty()) return errorJson("Wallet address unavailable");
            try {
                WalletRepository repo = new WalletRepository(appContext);
                return repo.submitKeySwitch(rpcUrl, address);
            } catch (Exception e) {
                return errorJson("key_switch failed: " + safeMessage(e));
            }
        }

        private JSONObject handleTokens() throws Exception {
            JSONObject info = safeWalletInfo();
            if (info.has("error")) return info;
            String rpcUrl = info.optString("rpc_url", UrlSecurityValidator.DEFAULT_RPC);
            String address = info.optString("address", "");
            WalletRepository repo = new WalletRepository(appContext);
            org.json.JSONArray tokens = repo.fetchTokensFast(rpcUrl, address);
            JSONObject out = new JSONObject();
            out.put("tokens", tokens);
            out.put("count", tokens.length());
            out.put("wallet_address", address);
            return out;
        }

        private JSONObject handleFheEncrypt(IHTTPSession session) throws Exception {
            if (!OctraNative.getInstance().isWalletLoaded()) {
                return errorJson("Wallet not loaded");
            }
            JSONObject body = parsePostBody(session);
            if (!body.has("value")) {
                return errorJson("missing value");
            }
            long value = body.optLong("value");
            String resultStr = OctraNative.getInstance().fheEncrypt(value);
            if (resultStr == null || resultStr.isEmpty()) {
                return errorJson("fheEncrypt native call returned empty");
            }
            return new JSONObject(resultStr);
        }

        private JSONObject handleFheDecrypt(IHTTPSession session) throws Exception {
            if (!OctraNative.getInstance().isWalletLoaded()) {
                return errorJson("Wallet not loaded");
            }
            JSONObject body = parsePostBody(session);
            if (!body.has("ciphertext")) {
                return errorJson("missing ciphertext");
            }
            String ciphertext = body.optString("ciphertext", "");
            String resultStr = OctraNative.getInstance().fheDecrypt(ciphertext);
            if (resultStr == null || resultStr.isEmpty()) {
                return errorJson("fheDecrypt native call returned empty");
            }
            return new JSONObject(resultStr);
        }

        private Response handleBridgeSigner(IHTTPSession session) {
            try {
                JSONObject body = parsePostBody(session);
                String method = body.optString("method", "");
                if (!"bridgeStatus".equals(method) &&
                    !"bridgeHeader".equals(method) &&
                    !"bridgeMessagesByEpoch".equals(method) &&
                    !"bridgeProofByLeafIndex".equals(method) &&
                    !"bridgeClaimCalldata".equals(method)) {
                    return jsonError(400, "Method not allowed");
                }

                // Retrieve signer_url from system env or fallback
                String signerUrl = System.getenv("OCTRA_BRIDGE_SIGNER_URL");
                if (signerUrl == null || signerUrl.trim().isEmpty()) {
                    signerUrl = "https://relayer-002838819188.octra.network";
                }

                // Send request using OkHttpClient
                okhttp3.OkHttpClient client = new okhttp3.OkHttpClient.Builder()
                        .connectTimeout(15, java.util.concurrent.TimeUnit.SECONDS)
                        .readTimeout(30, java.util.concurrent.TimeUnit.SECONDS)
                        .writeTimeout(15, java.util.concurrent.TimeUnit.SECONDS)
                        .proxySelector(new java.net.ProxySelector() {
                            @Override
                            public java.util.List<java.net.Proxy> select(java.net.URI uri) {
                                try {
                                    if (TorProxyStore.isEnabled(appContext)) {
                                        java.net.Proxy proxy = TorProxyStore.getActiveProxy(appContext);
                                        if (proxy != null) {
                                            return java.util.Collections.singletonList(proxy);
                                        }
                                    }
                                } catch (Exception e) {
                                    Log.e(TAG, "Bridge ProxySelector error: " + e.getMessage());
                                }
                                return java.util.Collections.singletonList(java.net.Proxy.NO_PROXY);
                            }

                            @Override
                            public void connectFailed(java.net.URI uri, java.net.SocketAddress sa, java.io.IOException ioe) {
                                Log.w(TAG, "Bridge Proxy connection failed: " + ioe.getMessage());
                            }
                        })
                        .build();

                okhttp3.MediaType mediaType = okhttp3.MediaType.get("application/json; charset=utf-8");
                okhttp3.RequestBody reqBody = okhttp3.RequestBody.create(body.toString(), mediaType);
                okhttp3.Request request = new okhttp3.Request.Builder()
                        .url(signerUrl)
                        .post(reqBody)
                        .build();

                try (okhttp3.Response response = client.newCall(request).execute()) {
                    String respStr = "";
                    if (response.body() != null) {
                        respStr = response.body().string();
                    }
                    Response.IStatus status = Response.Status.lookup(response.code());
                    if (status == null) {
                        status = Response.Status.INTERNAL_ERROR;
                    }
                    return newFixedLengthResponse(status, "application/json", respStr);
                }
            } catch (Exception e) {
                Log.e("LocalWebServer", "Bridge signer proxy error: " + e.getMessage());
                return jsonError(502, "Bridge signer unavailable: " + safeMessage(e));
            }
        }
    }
}
