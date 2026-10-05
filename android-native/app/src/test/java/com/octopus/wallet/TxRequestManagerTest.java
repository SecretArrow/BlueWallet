package com.octopus.wallet;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import org.junit.Test;

/**
 * Pure-JVM tests for approval-request tracking (no Android framework).
 */
public class TxRequestManagerTest {

    @Test
    public void createRejectsNullAndEmpty() {
        try {
            TxRequestManager.createRequest(null);
            fail("expected");
        } catch (IllegalArgumentException expected) {
        }
        try {
            TxRequestManager.createRequest("");
            fail("expected");
        } catch (IllegalArgumentException expected) {
        }
    }

    @Test
    public void createRejectsDuplicates() {
        String id = "test-dup-" + System.nanoTime();
        TxRequestManager.createRequest(id);
        try {
            try {
                TxRequestManager.createRequest(id);
                fail("expected duplicate rejection");
            } catch (IllegalStateException expected) {
            }
        } finally {
            TxRequestManager.removeRequest(id);
        }
    }

    @Test
    public void nullIdsAreSafeNoops() {
        assertNull(TxRequestManager.getRequest(null));
        TxRequestManager.removeRequest(null); // must not throw (CHM rejects null)
        TxRequestManager.completeRequest(null, true, "h", null); // must not throw
    }

    @Test
    public void completeMissingIdIsNoop() {
        TxRequestManager.completeRequest("no-such-id", false, null, "x"); // must not throw
        assertNull(TxRequestManager.getRequest("no-such-id"));
    }

    @Test
    public void completeWakesWaiterWithVerdict() throws Exception {
        String id = "test-wake-" + System.nanoTime();
        TxRequestManager.TxRequest req = TxRequestManager.createRequest(id);
        try {
            final boolean[] woke = {false};
            Thread t = new Thread(() -> {
                try {
                    req.latch.await();
                    woke[0] = true;
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            });
            t.start();
            TxRequestManager.completeRequest(id, true, "hash123", null);
            t.join(2000);
            assertTrue("waiter must wake", woke[0]);
            assertTrue(req.approved);
            assertEquals("hash123", req.txHash);
        } finally {
            TxRequestManager.removeRequest(id);
        }
        assertNull(TxRequestManager.getRequest(id));
    }

    @Test
    public void purgeDropsOnlyStaleEntries() {
        String fresh = "test-fresh-" + System.nanoTime();
        TxRequestManager.createRequest(fresh);
        try {
            long now = System.currentTimeMillis();
            // Nothing is older than 1h here → nothing purged.
            TxRequestManager.purgeOlderThan(now, 3600_000L);
            assertTrue(TxRequestManager.getRequest(fresh) != null);
            // TTL 0 with future now → everything stale.
            TxRequestManager.purgeOlderThan(now + 3600_000L, 0L);
            assertNull(TxRequestManager.getRequest(fresh));
        } finally {
            TxRequestManager.removeRequest(fresh);
        }
        assertFalse(TxRequestManager.trackedCount() < 0);
    }
}
