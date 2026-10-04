package com.octopus.wallet;

import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;

/**
 * Utility class to synchronize transaction approvals between the background local HTTP server
 * and the foreground confirmation dialog activity.
 */
public class TxRequestManager {

    public static class TxRequest {
        public final String id;
        public final CountDownLatch latch = new CountDownLatch(1);
        public boolean approved = false;
        public String txHash;
        public String error;

        public TxRequest(String id) {
            this.id = id;
        }
    }

    private static final ConcurrentHashMap<String, TxRequest> requests = new ConcurrentHashMap<>();

    public static TxRequest createRequest(String id) {
        TxRequest req = new TxRequest(id);
        requests.put(id, req);
        return req;
    }

    public static TxRequest getRequest(String id) {
        return requests.get(id);
    }

    public static void removeRequest(String id) {
        requests.remove(id);
    }

    public static void completeRequest(String id, boolean approved, String txHash, String error) {
        TxRequest req = requests.get(id);
        if (req != null) {
            req.approved = approved;
            req.txHash = txHash;
            req.error = error;
            req.latch.countDown();
        }
    }
}
