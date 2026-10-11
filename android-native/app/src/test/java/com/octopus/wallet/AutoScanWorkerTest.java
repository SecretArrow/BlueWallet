package com.octopus.wallet;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * Pure-JVM tests for the scan-notification bookkeeping (no Android
 * framework): every new incoming tx must notify exactly once, even when
 * several arrive between two scans, and notification ids must not collide
 * in a 16-bit bucket.
 */
public class AutoScanWorkerTest {

    @Test
    public void notificationIdFor_usesFullHashRange() {
        int a = AutoScanWorker.notificationIdFor("abc");
        int b = AutoScanWorker.notificationIdFor("abc");
        assertEquals(a, b);
        // Must not be masked to 16 bits (old behavior capped at 65535).
        boolean wide = false;
        boolean nonNegative = true;
        for (int i = 0; i < 2000; i++) {
            int id = AutoScanWorker.notificationIdFor("tx-" + i);
            if (id < 0) nonNegative = false;
            if (id - 5300 > 0xffff) {
                wide = true;
            }
        }
        assertTrue("ids must stay non-negative", nonNegative);
        assertTrue("ids must use more than 16 bits across inputs", wide);
        assertEquals(5300, AutoScanWorker.notificationIdFor(null));
    }

    @Test
    public void recordNotified_appendsAndPrunesOldest() {
        List<String> cur = new ArrayList<>(Arrays.asList("h1", "h2"));
        List<String> out = AutoScanWorker.recordNotified(cur, "h3", 3);
        assertEquals(Arrays.asList("h1", "h2", "h3"), out);
        // Re-notify moves to the end (keeps newest), no duplicates.
        out = AutoScanWorker.recordNotified(out, "h1", 3);
        assertEquals(Arrays.asList("h2", "h3", "h1"), out);
        // Prunes oldest beyond the cap.
        out = AutoScanWorker.recordNotified(out, "h4", 3);
        assertEquals(Arrays.asList("h3", "h1", "h4"), out);
        assertEquals(3, out.size());
    }

    @Test
    public void parseHistoryArray_toleratesAlternateShapes() throws Exception {
        assertTrue(WalletRepository.parseHistoryArray(null).isEmpty());
        assertTrue(WalletRepository.parseHistoryArray(new JSONObject()).isEmpty());
        assertTrue(WalletRepository.parseHistoryArray(
                new JSONObject("{\"transactions\":[{\"hash\":\"a\"},null]}")).size() == 1);
        assertEquals(2, WalletRepository.parseHistoryArray(
                new JSONObject("{\"history\":[{\"hash\":\"a\"},{\"hash\":\"b\"}]}")).size());
        assertEquals(1, WalletRepository.parseHistoryArray(
                new JSONObject("{\"txs\":[{\"hash\":\"c\"}]}")).size());
    }
}
