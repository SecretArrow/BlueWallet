package com.octopus.wallet;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import com.octopus.wallet.LocalWebServerService.OctraHttpServer;

import org.junit.Test;

import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Pure-JVM tests for local-server auth and parameter validation
 * (no sockets, no Android framework beyond no-op Log stubs).
 */
public class LocalServerValidationTest {

    private static Map<String, List<String>> qp(String key, String value) {
        Map<String, List<String>> m = new HashMap<>();
        m.put(key, Collections.singletonList(value));
        return m;
    }

    // ── auth ────────────────────────────────────────────────────────────

    @Test
    public void auth_acceptsExactBearerToken() {
        assertTrue(OctraHttpServer.isAuthorizedToken("abc123", "Bearer abc123"));
        assertTrue(OctraHttpServer.isAuthorizedToken("abc123", "Bearer   abc123  "));
    }

    @Test
    public void auth_rejectsMismatchAndMalformed() {
        assertFalse(OctraHttpServer.isAuthorizedToken("abc123", "Bearer wrong"));
        assertFalse(OctraHttpServer.isAuthorizedToken("abc123", "Bearer "));
        assertFalse(OctraHttpServer.isAuthorizedToken("abc123", "Bearer"));
        assertFalse(OctraHttpServer.isAuthorizedToken("abc123", "Basic abc123"));
        assertFalse(OctraHttpServer.isAuthorizedToken("abc123", null));
        assertFalse(OctraHttpServer.isAuthorizedToken("abc123", ""));
    }

    @Test
    public void auth_failClosedWithoutConfiguredToken() {
        // An empty/missing server token must deny everything, never open up.
        assertFalse(OctraHttpServer.isAuthorizedToken(null, "Bearer abc123"));
        assertFalse(OctraHttpServer.isAuthorizedToken("", "Bearer abc123"));
        assertFalse(OctraHttpServer.isAuthorizedToken("", ""));
    }

    // ── bounded ints ────────────────────────────────────────────────────

    @Test
    public void boundedInt_defaultsAndClamps() {
        assertEquals(20, OctraHttpServer.parseBoundedInt(new HashMap<>(), "limit", 20, 1, 200));
        assertEquals(50, OctraHttpServer.parseBoundedInt(qp("limit", "50"), "limit", 20, 1, 200));
        assertEquals(20, OctraHttpServer.parseBoundedInt(qp("limit", "abc"), "limit", 20, 1, 200));
        assertEquals(1, OctraHttpServer.parseBoundedInt(qp("limit", "-5"), "limit", 20, 1, 200));
        assertEquals(200, OctraHttpServer.parseBoundedInt(qp("limit", "99999"), "limit", 20, 1, 200));
        assertEquals(0, OctraHttpServer.parseBoundedInt(qp("offset", "-1"), "offset", 0, 0, 1000000));
    }

    // ── required fields ─────────────────────────────────────────────────

    @Test
    public void requireNonEmpty_trimsAndRejectsBlank() throws Exception {
        assertEquals("x", OctraHttpServer.requireNonEmpty("  x  ", "field"));
        for (String bad : new String[]{null, "", "   "}) {
            try {
                OctraHttpServer.requireNonEmpty(bad, "hash");
                fail("expected BadRequestException");
            } catch (LocalWebServerService.BadRequestException e) {
                assertTrue(e.getMessage().contains("hash"));
            }
        }
    }

    @Test
    public void requireUintString_acceptsOnlyDigits() throws Exception {
        assertEquals("0", OctraHttpServer.requireUintString("0", "amount"));
        assertEquals("1000", OctraHttpServer.requireUintString("1000", "ou"));
        for (String bad : new String[]{"", "  ", "-5", "1.5", "1e3", "0x10", "12a"}) {
            try {
                OctraHttpServer.requireUintString(bad, "amount");
                fail("expected BadRequestException for: '" + bad + "'");
            } catch (LocalWebServerService.BadRequestException e) {
                assertTrue(e.getMessage().contains("amount"));
            }
        }
        // Multi-value params: first value wins (NanoHTTPD convention).
        Map<String, List<String>> multi = new HashMap<>();
        multi.put("limit", Arrays.asList("10", "20"));
        assertEquals(10, OctraHttpServer.parseBoundedInt(multi, "limit", 20, 1, 200));
    }
}
