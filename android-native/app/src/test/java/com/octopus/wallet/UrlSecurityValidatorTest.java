package com.octopus.wallet;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/**
 * Pure-JVM tests for URL normalization (no Android framework needed —
 * the validator runs on {@code java.net.URI}).
 */
public class UrlSecurityValidatorTest {

    @Test
    public void normalizeRpcUrl_emptyFallsBackToDefault() {
        assertEquals(UrlSecurityValidator.DEFAULT_RPC, UrlSecurityValidator.normalizeRpcUrl(null));
        assertEquals(UrlSecurityValidator.DEFAULT_RPC, UrlSecurityValidator.normalizeRpcUrl(""));
        assertEquals(UrlSecurityValidator.DEFAULT_RPC, UrlSecurityValidator.normalizeRpcUrl("   "));
    }

    @Test
    public void normalizeRpcUrl_keepsLiveHosts() {
        assertEquals("https://octra.network/rpc",
                UrlSecurityValidator.normalizeRpcUrl("https://octra.network/rpc"));
        assertEquals("https://devnet.octrascan.io/rpc",
                UrlSecurityValidator.normalizeRpcUrl("https://devnet.octrascan.io/rpc"));
    }

    @Test
    public void normalizeRpcUrl_migratesDeadHosts() {
        assertEquals("https://octra.network/rpc",
                UrlSecurityValidator.normalizeRpcUrl("http://46.101.86.250:8080"));
        assertEquals("https://octra.network/rpc",
                UrlSecurityValidator.normalizeRpcUrl("http://46.101.86.250:8080/"));
        assertEquals("https://devnet.octrascan.io/rpc",
                UrlSecurityValidator.normalizeRpcUrl("http://165.227.225.79:8080"));
        assertEquals("https://devnet.octrascan.io/rpc",
                UrlSecurityValidator.normalizeRpcUrl("http://165.227.225.79:8080/rpc"));
        assertEquals("https://octra.network/rpc",
                UrlSecurityValidator.normalizeRpcUrl("https://rpc.octrascan.io"));
        assertEquals("https://octra.network/rpc",
                UrlSecurityValidator.normalizeRpcUrl("https://rpc.octrascan.io/rpc"));
    }

    @Test
    public void normalizeRpcUrl_rejectsNonHttp() {
        assertNull(UrlSecurityValidator.normalizeRpcUrl("ftp://example.com/x"));
        assertNull(UrlSecurityValidator.normalizeRpcUrl("http://"));
        assertNull(UrlSecurityValidator.normalizeRpcUrl("not a url with spaces"));
    }

    @Test
    public void normalizeExplorerUrl_requiresHttps() {
        assertEquals("https://octrascan.io",
                UrlSecurityValidator.normalizeExplorerUrl("https://octrascan.io"));
        assertNull(UrlSecurityValidator.normalizeExplorerUrl("http://octrascan.io"));
        assertEquals(UrlSecurityValidator.DEFAULT_EXPLORER,
                UrlSecurityValidator.normalizeExplorerUrl(""));
    }

    @Test
    public void isValidRpcUrl_acceptsHttpAndHttps() {
        assertTrue(UrlSecurityValidator.isValidRpcUrl("https://octra.network/rpc"));
        assertTrue(UrlSecurityValidator.isValidRpcUrl("http://127.0.0.1:8420"));
        assertFalse(UrlSecurityValidator.isValidRpcUrl("ftp://x"));
        assertFalse(UrlSecurityValidator.isValidRpcUrl(""));
    }

    @Test
    public void isCleartextRpc_flagsOnlyExternalHttp() {
        assertTrue(UrlSecurityValidator.isCleartextRpc("http://example.com:8080/rpc"));
        assertFalse(UrlSecurityValidator.isCleartextRpc("https://octra.network/rpc"));
        assertFalse(UrlSecurityValidator.isCleartextRpc("http://127.0.0.1:8420"));
        assertFalse(UrlSecurityValidator.isCleartextRpc("http://localhost:3000"));
        assertFalse(UrlSecurityValidator.isCleartextRpc("not-a-url"));
    }
}
