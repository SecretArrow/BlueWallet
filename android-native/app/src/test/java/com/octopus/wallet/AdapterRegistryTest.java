package com.octopus.wallet;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.util.Arrays;
import java.util.Collections;

/**
 * Pure-JVM tests for the modular adapter registry + per-origin sessions.
 */
public class AdapterRegistryTest {

    @Test
    public void resolve_servesAllKnownDialects() {
        assertNotNull(AdapterRegistry.resolve("octra_accounts"));
        assertNotNull(AdapterRegistry.resolve("octra_requestAccounts"));
        assertNotNull(AdapterRegistry.resolve("octra_sendTransaction"));
        assertNotNull(AdapterRegistry.resolve("octra_networkInfo"));
        assertNotNull(AdapterRegistry.resolve("disconnect"));
        assertNotNull(AdapterRegistry.resolve("wallet_connect"));
        assertNotNull(AdapterRegistry.resolve("wallet_getBalance"));
        // Orion alias folds onto wallet_*.
        assertNotNull(AdapterRegistry.resolve("orion_wallet_connect"));
    }

    @Test
    public void resolve_rejectsUnknownAndEmpty() {
        assertNull(AdapterRegistry.resolve("eth_sendTransaction"));
        assertNull(AdapterRegistry.resolve(""));
        assertNull(AdapterRegistry.resolve(null));
        assertNull(AdapterRegistry.resolve("   "));
    }

    @Test
    public void octraAdapter_listsServedMethods() {
        OctraWalletAdapter adapter = new OctraWalletAdapter();
        assertEquals("octra", adapter.getAdapterId());
        assertTrue(adapter.supports("octra_accounts"));
        assertTrue(adapter.supports("wallet_ping"));
        assertFalse(adapter.supports("eth_accounts"));
        assertFalse(adapter.supports(null));
    }

    @Test
    public void sessions_connectDisconnectPerOrigin() {
        DappSessionManager sessions = new DappSessionManager();
        String page = "https://example.com/app";
        assertFalse(sessions.isConnected(page));
        assertEquals("", sessions.addressFor(page));

        sessions.connect(page, "oct1abc", Arrays.asList("accounts"));
        assertTrue(sessions.isConnected(page));
        assertEquals("oct1abc", sessions.addressFor(page));
        assertEquals(Arrays.asList("accounts"), sessions.permissionsFor(page));

        // A different origin is unaffected (origin isolation).
        assertFalse(sessions.isConnected("https://other.io/"));
        assertEquals("", sessions.addressFor("https://other.io/"));

        sessions.disconnect(page);
        assertFalse(sessions.isConnected(page));
    }

    @Test
    public void sessions_defaultPermissionsWhenNoneGiven() {
        DappSessionManager sessions = new DappSessionManager();
        sessions.connect("https://example.com/", "oct1abc", null);
        assertEquals(Collections.singletonList("accounts"),
                sessions.permissionsFor("https://example.com/"));
    }

    @Test
    public void sessions_hostOf_normalizes() {
        assertEquals("example.com",
                DappSessionManager.hostOf("https://Example.COM:443/a?x=1#y"));
        assertEquals("", DappSessionManager.hostOf(null));
        assertEquals("", DappSessionManager.hostOf("not a url"));
    }

    @Test
    public void sessions_revokeWithNullContextDropsSessionOnly() {
        DappSessionManager sessions = new DappSessionManager();
        sessions.connect("https://example.com/", "oct1abc", null);
        sessions.revoke(null, "example.com");
        assertFalse(sessions.isConnected("https://example.com/"));
    }

    @Test
    public void resolve_servesWalletSendAndCallViewAliases() {
        // Resolve via registry (canonical + orion_ fold).
        assertNotNull(AdapterRegistry.resolve("wallet_sendTransaction"));
        assertNotNull(AdapterRegistry.resolve("wallet_callView"));
        assertNotNull(AdapterRegistry.resolve("orion_wallet_sendTransaction"));
        assertNotNull(AdapterRegistry.resolve("orion_wallet_callView"));
        // Adapter dispatch set carries both twins alongside legacy.
        OctraWalletAdapter adapter = new OctraWalletAdapter();
        assertTrue(adapter.supports("wallet_sendTransaction"));
        assertTrue(adapter.supports("wallet_callView"));
        assertTrue(adapter.supports("octra_sendTransaction"));
        assertTrue(adapter.supports("octra_callView"));
        // Protocol + registry agree (supported = dispatched, never silently dropped).
        assertTrue(DappBridgeProtocol.isSupported("wallet_sendTransaction"));
        assertTrue(DappBridgeProtocol.isSupported("wallet_callView"));
        assertTrue(AdapterRegistry.isSupported("wallet_sendTransaction"));
        assertTrue(AdapterRegistry.isSupported("wallet_callView"));
    }
}
