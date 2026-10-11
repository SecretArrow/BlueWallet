package com.octopus.wallet;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/**
 * Pure-JVM tests for the Startpage recent-visits policy (filtering + dedup).
 */
public class RecentVisitsStoreTest {

    @Test
    public void isRecordable_acceptsHttpWebsites() {
        assertTrue(RecentVisitsStore.isRecordable("https://devnet.octrascan.io"));
        assertTrue(RecentVisitsStore.isRecordable("http://example.com/a?b=1"));
    }

    @Test
    public void isRecordable_rejectsInternalBlankAndErrorSchemes() {
        String[] bad = {
                null, "", "   ", "about:blank", "about:error",
                "chrome://newtab", "file:///sdcard/x.html",
                "data:text/html,hi", "javascript:alert(1)", "blob:https://x/y",
                "octra-wallet://connect?x=1", "octra-local://callback?ok=true",
                "oct://circle123/index.html", "intent://scan/#Intent;scheme=zxing;end",
                "not a url", "example.com-no-scheme",
        };
        for (String url : bad) {
            assertFalse("must not record: " + url, RecentVisitsStore.isRecordable(url));
        }
    }

    @Test
    public void isRecordable_rejectsSensitiveQueryMaterial() {
        assertFalse(RecentVisitsStore.isRecordable("https://x.io/?mnemonic=word1+word2"));
        assertFalse(RecentVisitsStore.isRecordable("https://x.io/#private_key=abc"));
        assertFalse(RecentVisitsStore.isRecordable("https://x.io/login?password=1"));
        assertFalse(RecentVisitsStore.isRecordable("https://x.io/?pin=123456"));
    }

    @Test
    public void normalizeForDedup_stripsFragmentAndRootSlash() {
        assertEquals("https://x.io/a",
                RecentVisitsStore.normalizeForDedup("https://x.io/a#frag"));
        assertEquals("https://x.io",
                RecentVisitsStore.normalizeForDedup("https://x.io/"));
        assertEquals("https://x.io/a?b=1",
                RecentVisitsStore.normalizeForDedup("  https://x.io/a?b=1  "));
        assertEquals("", RecentVisitsStore.normalizeForDedup(null));
    }

    @Test
    public void domainOf_extractsLowercaseHost() {
        assertEquals("devnet.octrascan.io",
                RecentVisitsStore.domainOf("https://DevNet.OctraScan.io/path"));
        assertEquals("", RecentVisitsStore.domainOf("not a url"));
    }

    @Test
    public void maxEntries_isTen() {
        assertEquals(10, RecentVisitsStore.MAX_ENTRIES);
    }
}
