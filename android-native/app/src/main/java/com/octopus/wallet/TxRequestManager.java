package com.octopus.wallet;

import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;

/**
 * Utility class to synchronize transaction approvals between the background local HTTP server
 * and the foreground confirmation dialog activity.
 */
public class TxRequestManager {

    /** Requests older than this are purged on create (fail-safe vs leaks). */
    static final long REQUEST_TTL_MS = 10 * 60 * 1000L;

    /** Max tracked requests; beyond this, creation fails loudly. */
    static final int MAX_TRACKED = 500;

    public static class TxRequest {
        public final String id;
        public final CountDownLatch latch = new CountDownLatch(1);
        public final long createdAtMs;
        public boolean approved = false;
        public String txHash;
        public String error;

        public TxRequest(String id) {
            if (id == null || id.isEmpty()) {
                throw new IllegalArgumentException("TxRequest id must not be empty");
            }
            this.id = id;
            this.createdAtMs = System.currentTimeMillis();
        }
    }

    private static final ConcurrentHashMap<String, TxRequest> requests = new ConcurrentHashMap<>();

    /**
     * Track a new approval request. Rejects null/empty/duplicate ids loudly —
     * an overwritten entry would deliver one dApp's verdict to another.
     */
    public static TxRequest createRequest(String id) {
        if (id == null || id.isEmpty()) {
            throw new IllegalArgumentException("TxRequest id must not be empty");
        }
        purgeOlderThan(System.currentTimeMillis(), REQUEST_TTL_MS);
        if (requests.size() >= MAX_TRACKED) {
            throw new IllegalStateException("Too many pending approval requests");
        }
        TxRequest req = new TxRequest(id);
        TxRequest prev = requests.putIfAbsent(id, req);
        if (prev != null) {
            throw new IllegalStateException("Duplicate approval request id: " + id);
        }
        return req;
    }

    public static TxRequest getRequest(String id) {
        if (id == null) return null;
        return requests.get(id);
    }

    public static void removeRequest(String id) {
        if (id == null) return;
        requests.remove(id);
    }

    public static void completeRequest(String id, boolean approved, String txHash, String error) {
        if (id == null) return;
        TxRequest req = requests.get(id);
        if (req != null) {
            req.approved = approved;
            req.txHash = txHash;
            req.error = error;
            req.latch.countDown();
        }
    }

    /** Drop entries older than {@code ttlMs}. Package-visible for tests. */
    static void purgeOlderThan(long nowMs, long ttlMs) {
        for (java.util.Map.Entry<String, TxRequest> e : requests.entrySet()) {
            if (nowMs - e.getValue().createdAtMs > ttlMs) {
                requests.remove(e.getKey(), e.getValue());
            }
        }
    }

    /** Test-only hook: current tracked count. */
    static int trackedCount() {
        return requests.size();
    }
}
