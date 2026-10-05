package com.octopus.wallet;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

/**
 * Pure-JVM tests for dApp origin normalization.
 */
public class DappOriginStoreTest {

    @Test
    public void normalizeHost_stripsSchemePathQueryFragment() {
        assertEquals("example.com",
                DappOriginStore.normalizeHost("https://Example.COM:443/a/b?x=1#frag"));
        assertEquals("example.com",
                DappOriginStore.normalizeHost("http://example.com/"));
        assertEquals("", DappOriginStore.normalizeHost(null));
        assertEquals("", DappOriginStore.normalizeHost("   "));
    }

    @Test
    public void normalizeHost_stripsPorts() {
        // Ports never matched Uri.getHost() output, so keeping them made
        // entries silently ineffective — now stripped on write AND read.
        assertEquals("example.com", DappOriginStore.normalizeHost("example.com:8080"));
        assertEquals("localhost", DappOriginStore.normalizeHost("localhost:3000"));
        assertEquals("127.0.0.1", DappOriginStore.normalizeHost("127.0.0.1:8420"));
    }

    @Test
    public void normalizeHost_stripsTrailingDots() {
        assertEquals("example.com", DappOriginStore.normalizeHost("example.com."));
    }

    @Test
    public void normalizeHost_keepsIpv6Brackets() {
        assertEquals("[::1]", DappOriginStore.normalizeHost("[::1]:8080"));
        assertEquals("[::1]", DappOriginStore.normalizeHost("[::1]"));
    }

    @Test
    public void normalizeHost_keepsNonNumericColonSuffix() {
        // Not a port (no digits) — preserved verbatim rather than mangled.
        assertEquals("weird:abc", DappOriginStore.normalizeHost("weird:abc"));
        assertEquals("example.com", DappOriginStore.normalizeHost("example.com:"));
    }
}
