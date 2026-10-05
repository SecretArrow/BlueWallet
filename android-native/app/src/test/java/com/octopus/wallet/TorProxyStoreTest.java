package com.octopus.wallet;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.fail;

import org.junit.Test;

/**
 * Pure-JVM tests for Tor proxy validation.
 */
public class TorProxyStoreTest {

    @Test
    public void validateProxy_acceptsSaneValues() {
        TorProxyStore.validateProxy("127.0.0.1", 9050, "SOCKS");
        TorProxyStore.validateProxy("example.onion", 8118, "http");
        TorProxyStore.validateProxy("h", 1, "socks");
        TorProxyStore.validateProxy("h", 65535, "HTTP");
    }

    @Test
    public void validateProxy_rejectsGarbage() {
        // {host, port, type} — port is already int here (UI parses text first).
        Object[][] bad = {
                {null, 9050, "SOCKS"},
                {"", 9050, "SOCKS"},
                {"   ", 9050, "SOCKS"},
                {"h", 0, "SOCKS"},
                {"h", -1, "SOCKS"},
                {"h", 65536, "SOCKS"},
                {"h", 9050, ""},
                {"h", 9050, "FTP"},
                {"h", 9050, null},
        };
        for (Object[] b : bad) {
            try {
                TorProxyStore.validateProxy((String) b[0], (Integer) b[1], (String) b[2]);
                fail("expected for host=" + b[0] + " port=" + b[1] + " type=" + b[2]);
            } catch (IllegalArgumentException expected) {
            }
        }
    }

    @Test
    public void canonicalType_normalizes() {
        assertEquals("SOCKS", TorProxyStore.canonicalType("socks"));
        assertEquals("SOCKS", TorProxyStore.canonicalType("Socks"));
        assertEquals("HTTP", TorProxyStore.canonicalType("http"));
        assertEquals("SOCKS", TorProxyStore.canonicalType("anything-else"));
    }
}
