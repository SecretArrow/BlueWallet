package com.octopus.wallet;

import android.os.Handler;
import android.os.Looper;
import android.webkit.JavascriptInterface;

import java.lang.ref.WeakReference;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Minimal, hardened {@code @JavascriptInterface} for {@code window.octra}.
 *
 * <p>Only three entry points are exposed: {@code connect}, {@code request}
 * and {@code cancel}. Every call validates origin, method name and payload
 * size before dispatching to {@link AdapterRegistry}. Parallel requests are
 * tracked by id with a timeout; duplicates are rejected; navigation,
 * tab-close and WebView-destroy cancel everything outstanding so no late
 * callback ever touches a dead page. Payloads that fail validation and
 * unknown methods get explicit errors — never silent drops, never mocks.
 */
public final class DappJsBridge {

    /** Largest accepted params JSON (256 KB — dApp calls are small objects). */
    public static final int MAX_PAYLOAD_BYTES = 256 * 1024;

    /** Reads time out after 30 s; approvals (user think time) after 5 min. */
    public static final long READ_TIMEOUT_MS = 30_000L;
    public static final long APPROVAL_TIMEOUT_MS = 5 * 60_000L;

    /** Host side, held weakly so the bridge never leaks the Activity. */
    public interface Host extends WalletAdapterContext {
        /** Current page URL at call time. */
        String currentUrl();

        /** True when the current origin may use the wallet (allowlist). */
        boolean isOriginAllowed(String url);
    }

    private static final class Pending {
        final String origin;
        final String method;
        final long createdAt;
        final Runnable timeoutTask;

        Pending(String origin, String method, long createdAt, Runnable timeoutTask) {
            this.origin = origin;
            this.method = method;
            this.createdAt = createdAt;
            this.timeoutTask = timeoutTask;
        }
    }

    private final WeakReference<Host> hostRef;
    private final ConcurrentHashMap<Integer, Pending> pending = new ConcurrentHashMap<>();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private volatile boolean destroyed = false;

    public DappJsBridge(Host host, DappSessionManager sessions) {
        this.hostRef = new WeakReference<>(host);
        // sessions is owned by the host; kept out of the bridge so teardown
        // has exactly one owner (destroy() only drops pending requests).
    }

    @JavascriptInterface
    public void connect(final int requestId) {
        final Host host = hostRef.get();
        if (host == null || destroyed) return;
        mainHandler.post(() -> handleConnect(host, requestId));
    }

    @JavascriptInterface
    public void request(final int requestId, final String method, final String paramsJson) {
        final Host host = hostRef.get();
        if (host == null || destroyed) return;
        // Copy to finals for the hop to the UI thread.
        final String m = method;
        final String p = paramsJson == null ? "[]" : paramsJson;
        mainHandler.post(() -> handleRequest(host, requestId, m, p));
    }

    @JavascriptInterface
    public void cancel(final int requestId) {
        Pending removed = pending.remove(requestId);
        if (removed != null && removed.timeoutTask != null) {
            mainHandler.removeCallbacks(removed.timeoutTask);
        }
    }

    /** Cancel everything outstanding (navigation / tab-close / destroy). */
    public void cancelAll(String reason) {
        for (Integer id : pending.keySet()) {
            Pending r = pending.remove(id);
            if (r != null && r.timeoutTask != null) mainHandler.removeCallbacks(r.timeoutTask);
            Host host = hostRef.get();
            if (host != null && !destroyed && reason != null) {
                try {
                    host.sendError(id, reason, DappBridgeProtocol.DISCONNECTED);
                } catch (Exception ignored) {
                    // Teardown path: never crash for a late error post.
                }
            }
        }
    }

    /** WebView is going away: stop timers, drop state, never call back. */
    public void destroy() {
        destroyed = true;
        for (Pending r : pending.values()) {
            if (r.timeoutTask != null) mainHandler.removeCallbacks(r.timeoutTask);
        }
        pending.clear();
    }

    public boolean isPending(int requestId) {
        return pending.containsKey(requestId);
    }

    int pendingCount() {
        return pending.size();
    }

    // ── Internals (UI thread) ─────────────────────────────────────────────

    private void handleConnect(Host host, int requestId) {
        if (destroyed || !host.isAlive()) return;
        String origin = safeUrl(host.currentUrl());
        if (origin.isEmpty()) {
            host.sendError(requestId, "Cannot determine page origin",
                    DappBridgeProtocol.UNAUTHORIZED);
            return;
        }
        if (!track(host, requestId, "connect", origin, "[]", true)) return;
        // Connect always goes through the approval-gated account flow so the
        // origin allowlist + session stay consistent in one place.
        dispatch(host, requestId, DappBridgeProtocol.REQUEST_ACCOUNTS, "[]", origin);
    }

    private void handleRequest(Host host, int requestId, String method, String paramsJson) {
        if (destroyed || !host.isAlive()) return;
        String origin = safeUrl(host.currentUrl());
        if (origin.isEmpty()) {
            host.sendError(requestId, "Cannot determine page origin",
                    DappBridgeProtocol.UNAUTHORIZED);
            return;
        }
        String rawMethod = method == null ? "" : method.trim();
        if (rawMethod.isEmpty()) {
            host.sendError(requestId, "Missing method", DappBridgeProtocol.UNSUPPORTED_METHOD);
            return;
        }
        if (rawMethod.length() > 128) {
            host.sendError(requestId, "Method name too long",
                    DappBridgeProtocol.UNSUPPORTED_METHOD);
            return;
        }
        if (paramsJson != null && paramsJson.length() > MAX_PAYLOAD_BYTES) {
            host.sendError(requestId, "Params too large (limit " + MAX_PAYLOAD_BYTES + " chars)");
            return;
        }
        String canonical = DappBridgeProtocol.canonicalize(rawMethod);
        // Reads that need no session still require a known method; anything
        // else is an explicit unsupported error (never silent, never mocked).
        WalletAdapter adapter = AdapterRegistry.resolve(canonical);
        if (adapter == null) {
            if (DappBridgeProtocol.isKnownUnsupported(canonical)) {
                if (track(host, requestId, canonical, origin, paramsJson, false)) {
                    complete(host, requestId);
                    host.sendError(requestId,
                            rawMethod + " is not supported by this wallet"
                                    + " (sign-only submission split, message signing"
                                    + " and FHE-private primitives stay in the wallet UI)",
                            DappBridgeProtocol.UNSUPPORTED_METHOD);
                }
            } else {
                if (track(host, requestId, canonical, origin, paramsJson, false)) {
                    complete(host, requestId);
                    host.sendError(requestId, "Unsupported method: " + rawMethod,
                            DappBridgeProtocol.UNSUPPORTED_METHOD);
                }
            }
            return;
        }
        boolean needsSession = needsSession(canonical);
        if (needsSession && !host.isConnected()
                && !DappBridgeProtocol.REQUEST_ACCOUNTS.equals(canonical)) {
            if (track(host, requestId, canonical, origin, paramsJson, false)) {
                complete(host, requestId);
                host.sendError(requestId, "Not connected",
                        DappBridgeProtocol.UNAUTHORIZED);
            }
            return;
        }
        if (!track(host, requestId, canonical, origin, paramsJson, needsApproval(canonical))) {
            return;
        }
        dispatch(host, requestId, canonical, paramsJson, origin);
    }

    private void dispatch(Host host, int requestId, String canonical,
                          String paramsJson, String origin) {
        WalletAdapter adapter = AdapterRegistry.resolve(canonical);
        if (adapter == null) {
            complete(host, requestId);
            host.sendError(requestId, "Unsupported method: " + canonical,
                    DappBridgeProtocol.UNSUPPORTED_METHOD);
            return;
        }
        boolean dispatched;
        try {
            dispatched = adapter.handle(new GuardedContext(host, requestId), requestId,
                    canonical, paramsJson);
        } catch (Exception e) {
            dispatched = true;
            if (!isGone(host, requestId)) {
                complete(host, requestId);
                host.sendError(requestId, e.getMessage() == null
                        ? "Request failed" : e.getMessage());
            } else {
                complete(host, requestId);
            }
            return;
        }
        if (!dispatched) {
            complete(host, requestId);
            host.sendError(requestId, "Unsupported method: " + canonical,
                    DappBridgeProtocol.UNSUPPORTED_METHOD);
        }
        // When dispatched, the adapter answers exactly once (or the timeout
        // below does). Approval-gated flows complete asynchronously.
    }

    /** Register a pending id; false when duplicate (caller must not proceed). */
    private boolean track(Host host, int requestId, String method, String origin,
                          String paramsJson, boolean approval) {
        long timeout = approval ? APPROVAL_TIMEOUT_MS : READ_TIMEOUT_MS;
        final int id = requestId;
        final Host h = host;
        Runnable timeoutTask = () -> {
            if (pending.remove(id) != null && !destroyed && h.isAlive()) {
                try {
                    h.sendError(id, "Request timed out", DappBridgeProtocol.NETWORK_UNAVAILABLE);
                } catch (Exception ignored) {
                    // Timeout teardown: best effort only.
                }
            }
        };
        Pending prev = pending.putIfAbsent(requestId,
                new Pending(origin, method, System.currentTimeMillis(), timeoutTask));
        if (prev != null) {
            host.sendError(requestId, "Duplicate request id: " + requestId);
            return false;
        }
        mainHandler.postDelayed(timeoutTask, timeout);
        return true;
    }

    private void complete(Host host, int requestId) {
        Pending r = pending.remove(requestId);
        if (r != null && r.timeoutTask != null) mainHandler.removeCallbacks(r.timeoutTask);
    }

    private boolean isGone(Host host, int requestId) {
        return destroyed || !host.isAlive() || !pending.containsKey(requestId);
    }

    private static boolean needsSession(String canonical) {
        // Pre-connect probes + teardown stay session-free; everything else
        // requires an approved origin session.
        return !("octra_accounts".equals(canonical)
                || "octra_chainId".equals(canonical)
                || "disconnect".equals(canonical)
                || "wallet_disconnect".equals(canonical)
                || "wallet_ping".equals(canonical));
    }

    private static boolean needsApproval(String canonical) {
        return DappBridgeProtocol.REQUEST_ACCOUNTS.equals(canonical)
                || "wallet_connect".equals(canonical)
                || "octra_sendTransaction".equals(canonical)
                || "octra_sendContractTransaction".equals(canonical)
                || "octra_callContract".equals(canonical)
                || "octra_switchNetwork".equals(canonical);
    }

    private static String safeUrl(String url) {
        return url == null ? "" : url.trim();
    }

    /**
     * Wraps the host so adapter completions clear tracking exactly once and
     * late callbacks after cancel/destroy are dropped.
     */
    private final class GuardedContext implements WalletAdapterContext {
        private final Host host;
        private final int requestId;

        GuardedContext(Host host, int requestId) {
            this.host = host;
            this.requestId = requestId;
        }

        @Override
        public String getOrigin() {
            return safeUrl(host.currentUrl());
        }

        @Override
        public String getConnectedAddress() {
            return host.getConnectedAddress();
        }

        @Override
        public boolean isConnected() {
            return host.isConnected();
        }

        @Override
        public String getWalletAddress() {
            return host.getWalletAddress();
        }

        @Override
        public String getWalletPublicKeyB64() {
            return host.getWalletPublicKeyB64();
        }

        @Override
        public String getRpcUrl() {
            return host.getRpcUrl();
        }

        @Override
        public String getChainId() {
            return host.getChainId();
        }

        @Override
        public org.json.JSONObject getNetworkInfo() {
            return host.getNetworkInfo();
        }

        @Override
        public java.util.List<String> getPermissions() {
            return host.getPermissions();
        }

        @Override
        public void setSessionConnected(String address, java.util.List<String> permissions) {
            host.setSessionConnected(address, permissions);
        }

        @Override
        public void clearSession() {
            host.clearSession();
        }

        @Override
        public void sendResult(int id, String resultJson) {
            if (id != requestId) return;
            Pending r = pending.remove(id);
            if (r == null) return;
            if (r.timeoutTask != null) mainHandler.removeCallbacks(r.timeoutTask);
            if (!destroyed && host.isAlive()) host.sendResult(id, resultJson);
        }

        @Override
        public void sendError(int id, String error, int code) {
            if (id != requestId) return;
            Pending r = pending.remove(id);
            if (r == null) return;
            if (r.timeoutTask != null) mainHandler.removeCallbacks(r.timeoutTask);
            if (!destroyed && host.isAlive()) host.sendError(id, error, code);
        }

        @Override
        public boolean isCancelled(int id) {
            return destroyed || !pending.containsKey(id);
        }

        @Override
        public boolean isAlive() {
            return !destroyed && host.isAlive();
        }

        @Override
        public java.util.concurrent.ExecutorService io() {
            return host.io();
        }

        @Override
        public void requestApproval(String title, String message, ApprovalCallback callback) {
            if (isCancelled(requestId)) return;
            host.requestApproval(title, message, approved -> {
                if (isCancelled(requestId)) return;
                callback.onDecision(approved);
            });
        }
    }
}
