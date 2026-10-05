package com.octopus.wallet;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/**
 * Pure-JVM tests for the dApp bridge wire registry (RFC-O-1 dual-stack).
 */
public class DappBridgeProtocolTest {

    @Test
    public void errorCodes_matchRfc() {
        assertEquals(0, DappBridgeProtocol.NO_CODE);
        assertEquals(4001, DappBridgeProtocol.USER_REJECTED);
        assertEquals(4100, DappBridgeProtocol.UNAUTHORIZED);
        assertEquals(4200, DappBridgeProtocol.UNSUPPORTED_METHOD);
        assertEquals(4900, DappBridgeProtocol.DISCONNECTED);
        assertEquals(4901, DappBridgeProtocol.NETWORK_UNAVAILABLE);
    }

    @Test
    public void canonicalize_trimsAndNullGuards() {
        assertEquals("octra_requestAccounts",
                DappBridgeProtocol.canonicalize("  octra_requestAccounts  "));
        assertEquals("", DappBridgeProtocol.canonicalize(null));
        assertEquals("", DappBridgeProtocol.canonicalize("   "));
    }

    @Test
    public void isSupported_coversBothDialects() {
        // Legacy dialect (existing clients keep working).
        assertTrue(DappBridgeProtocol.isSupported("octra_accounts"));
        assertTrue(DappBridgeProtocol.isSupported("octra_chainId"));
        assertTrue(DappBridgeProtocol.isSupported("octra_getBalance"));
        assertTrue(DappBridgeProtocol.isSupported("octra_sendTransaction"));
        assertTrue(DappBridgeProtocol.isSupported("octra_callContract"));
        assertTrue(DappBridgeProtocol.isSupported("octra_callView"));
        // RFC-O-1 aliases (new).
        assertTrue(DappBridgeProtocol.isSupported("octra_requestAccounts"));
        assertTrue(DappBridgeProtocol.isSupported("octra_getEncryptedBalance"));
        // Unknown.
        assertFalse(DappBridgeProtocol.isSupported("octra_broadcast"));
        assertFalse(DappBridgeProtocol.isSupported(""));
        assertFalse(DappBridgeProtocol.isSupported(null));
        assertFalse(DappBridgeProtocol.isSupported("eth_sendTransaction"));
    }
}
