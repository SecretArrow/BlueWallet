package com.octopus.wallet;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import com.octopus.wallet.LocalWebServerService.OctraHttpServer;

import org.json.JSONObject;
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
            } catch (OctraHttpServer.BadRequestException e) {
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
            } catch (OctraHttpServer.BadRequestException e) {
                assertTrue(e.getMessage().contains("amount"));
            }
        }
        // Multi-value params: first value wins (NanoHTTPD convention).
        Map<String, List<String>> multi = new HashMap<>();
        multi.put("limit", Arrays.asList("10", "20"));
        assertEquals(10, OctraHttpServer.parseBoundedInt(multi, "limit", 20, 1, 200));
    }

    // ── static asset MIME ───────────────────────────────────────────────

    // ── /api/transaction normalization ─────────────────────────────────

    /** Object values so JSONObject.NULL can be exercised too. */
    private static JSONObject tx(Object... kv) {
        if (kv.length % 2 != 0) {
            throw new IllegalArgumentException("tx() needs key/value pairs");
        }
        JSONObject o = new JSONObject();
        for (int i = 0; i < kv.length; i += 2) {
            try {
                o.put(String.valueOf(kv[i]), kv[i + 1]);
            } catch (Exception e) {
                throw new IllegalArgumentException(e);
            }
        }
        return o;
    }

    @Test
    public void normalizeTransaction_reportsFoundWithEpoch() throws Exception {
        JSONObject out = OctraHttpServer.normalizeTransaction("0xabc",
                tx("tx_hash", "0xabc", "epoch", "42", "status", "confirmed",
                        "block_height", "9"));
        assertTrue(out.getBoolean("found"));
        assertEquals("0xabc", out.getString("hash"));
        assertEquals(42L, out.getLong("epoch"));
        assertEquals("confirmed", out.getString("status"));
        assertEquals(9L, out.getLong("block_height"));
    }

    @Test
    public void normalizeTransaction_acceptsEpochIdSpelling() throws Exception {
        // Older node builds answer epoch_id instead of epoch.
        assertEquals(7L,
                OctraHttpServer.normalizeTransaction("0xa", tx("epoch_id", "7"))
                        .getLong("epoch"));
    }

    @Test
    public void normalizeTransaction_missingEpochIsZeroNotAbsent() throws Exception {
        JSONObject out = OctraHttpServer.normalizeTransaction("0xa", tx("status", "pending"));
        assertTrue(out.getBoolean("found"));
        // No epoch in the payload yet: reported as 0 so the poller retries,
        // never omitted (which would read as "unknown" downstream).
        assertEquals(0L, out.getLong("epoch"));
        assertEquals("pending", out.getString("status"));
        // A payload with no status at all still answers with an empty string
        // rather than dropping the field.
        assertEquals("",
                OctraHttpServer.normalizeTransaction("0xb", tx("epoch", "1"))
                        .getString("status"));
    }

    @Test
    public void normalizeTransaction_nullOrEmptyIsNotFound() throws Exception {
        for (JSONObject in : new JSONObject[]{null, new JSONObject()}) {
            JSONObject out = OctraHttpServer.normalizeTransaction("0xdead", in);
            assertFalse(out.getBoolean("found"));
            assertEquals("0xdead", out.getString("hash"));
            assertFalse("a miss must not fake an epoch", out.has("epoch"));
        }
    }

    @Test
    public void normalizeTransaction_surfacesRejectionReason() throws Exception {
        JSONObject in = new JSONObject();
        in.put("epoch", 3);
        in.put("error", "nonce too low");
        JSONObject out = OctraHttpServer.normalizeTransaction("0x1", in);
        assertEquals("nonce too low", out.getString("error_detail"));
        // JSONException on a null value would previously throw a 500.
        JSONObject withNull = tx("epoch", "1", "error", JSONObject.NULL);
        assertEquals(1L,
                OctraHttpServer.normalizeTransaction("0x2", withNull).getLong("epoch"));
    }

    @Test
    public void getMimeType_servesMjsAsScript() {
        // Browsers reject ES module imports served with a non-script type.
        assertEquals("application/javascript", OctraHttpServer.getMimeType("adapter/index.mjs"));
        assertEquals("application/javascript", OctraHttpServer.getMimeType("adapter/boot.mjs"));
        assertEquals("application/javascript", OctraHttpServer.getMimeType("swap.js"));
        assertEquals("text/html", OctraHttpServer.getMimeType("swap.html"));
        assertEquals("text/css", OctraHttpServer.getMimeType("style.css"));
        assertEquals("image/svg+xml", OctraHttpServer.getMimeType("logo.svg"));
    }

    @Test
    public void getMimeType_fallsBackForUnknownAndNull() {
        assertEquals("application/octet-stream", OctraHttpServer.getMimeType("notes.txt"));
        assertEquals("application/octet-stream", OctraHttpServer.getMimeType(""));
        assertEquals("application/octet-stream", OctraHttpServer.getMimeType("mjs"));
        assertEquals("application/octet-stream", OctraHttpServer.getMimeType(null));
    }
}
