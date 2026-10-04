package com.octopus.wallet;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

/**
 * Pure-JVM tests for the RPC dispatch layer (no network, no Android
 * framework). Branches that call {@code android.util.Log} are excluded here
 * (Log stubs crash on plain JVM) and covered by inspection + CI lint.
 */
public class OctraRpcClientTest {

    // ── call() validation (no network touched) ──────────────────────────

    @Test
    public void call_rejectsNullMethodWithoutNetwork() {
        long start = System.currentTimeMillis();
        try {
            OctraRpcClient.getInstance().call("http://127.0.0.1:1", null, new JSONArray());
            fail("expected IllegalArgumentException");
        } catch (IllegalArgumentException e) {
            assertTrue(e.getMessage().contains("non-empty"));
        } catch (Exception e) {
            fail("wrong exception type: " + e);
        }
        // Must fail fast: no retry sleeps, no connection attempts.
        assertTrue("validation must not touch the network",
                System.currentTimeMillis() - start < 2000);
    }

    @Test
    public void call_rejectsBlankMethodWithoutNetwork() {
        try {
            OctraRpcClient.getInstance().call("http://127.0.0.1:1", "   ", new JSONArray());
            fail("expected IllegalArgumentException");
        } catch (IllegalArgumentException expected) {
        } catch (Exception e) {
            fail("wrong exception type: " + e);
        }
    }

    @Test
    public void callWithRetry_doesNotRetryPermanentErrors() {
        long start = System.currentTimeMillis();
        try {
            OctraRpcClient.getInstance().callWithRetry("http://127.0.0.1:1", null, null, 5);
            fail("expected IllegalArgumentException");
        } catch (IllegalArgumentException expected) {
        } catch (Exception e) {
            fail("wrong exception type: " + e);
        }
        assertTrue("permanent errors must not be retried",
                System.currentTimeMillis() - start < 2000);
    }

    // ── endpoint builders ───────────────────────────────────────────────

    @Test
    public void buildRpcEndpoint_appendsRpcPath() {
        assertEquals("http://host:8080/rpc",
                OctraRpcClient.buildRpcEndpoint("http://host:8080"));
        assertEquals("https://octra.network/rpc",
                OctraRpcClient.buildRpcEndpoint("https://octra.network/rpc"));
        // Trailing slash is preserved (matches pre-refactor android.net.Uri
        // behavior); callers and the node tolerate it.
        assertEquals("https://octra.network/rpc/",
                OctraRpcClient.buildRpcEndpoint("https://octra.network/rpc/"));
    }

    @Test
    public void buildApiBase_stripsRpcSuffix() {
        assertEquals("http://host:8080",
                OctraRpcClient.buildApiBase("http://host:8080/rpc"));
        assertEquals("http://host:8080",
                OctraRpcClient.buildApiBase("http://host:8080"));
    }

    // ── envelope extraction ─────────────────────────────────────────────

    @Test
    public void extractResult_returnsObjectResult() throws Exception {
        JSONObject env = new JSONObject("{\"jsonrpc\":\"2.0\",\"result\":{\"a\":1},\"id\":1}");
        assertEquals(1, OctraRpcClient.extractResult(env).getInt("a"));
    }

    @Test
    public void extractResult_wrapsScalarAndArray() throws Exception {
        assertEquals("hi", OctraRpcClient.extractResult(
                new JSONObject("{\"result\":\"hi\"}")).getString("value"));
        assertEquals(2, OctraRpcClient.extractResult(
                new JSONObject("{\"result\":[1,2]}")).getJSONArray("value").length());
    }

    @Test
    public void extractResult_missingResultThrows() {
        try {
            OctraRpcClient.extractResult(new JSONObject("{\"jsonrpc\":\"2.0\",\"id\":1}"));
            fail("expected exception");
        } catch (Exception e) {
            assertTrue(e.getMessage().contains("missing 'result'"));
        }
    }

    @Test
    public void extractResult_nullResultThrows() {
        try {
            OctraRpcClient.extractResult(new JSONObject("{\"result\":null}"));
            fail("expected exception");
        } catch (Exception e) {
            assertTrue(e.getMessage() != null && !e.getMessage().isEmpty());
        }
    }

    @Test
    public void extractResult_rpcErrorEnvelopeThrowsWithMessage() {
        try {
            OctraRpcClient.extractResult(new JSONObject(
                    "{\"error\":{\"code\":-32000,\"message\":\"no funds\"}}"));
            fail("expected exception");
        } catch (Exception e) {
            assertEquals("no funds", e.getMessage());
        }
    }

    @Test
    public void throwOnRpcError_handlesAllShapes() throws Exception {
        // No error → silent pass on every path.
        OctraRpcClient.throwOnRpcError(new JSONObject("{\"result\":{}}"));
        OctraRpcClient.throwOnRpcError(new JSONObject("{\"error\":null}"));
        try {
            OctraRpcClient.throwOnRpcError(new JSONObject("{\"error\":{\"code\":1}}"));
            fail("expected");
        } catch (Exception e) {
            assertEquals("RPC error", e.getMessage());
        }
        try {
            OctraRpcClient.throwOnRpcError(new JSONObject("{\"error\":\"plain string\"}"));
            fail("expected");
        } catch (Exception e) {
            assertEquals("plain string", e.getMessage());
        }
        try {
            OctraRpcClient.throwOnRpcError(new JSONObject("{\"error\":42}"));
            fail("expected");
        } catch (Exception e) {
            assertEquals("42", e.getMessage());
        }
    }

    @Test
    public void extractResultOrNull_neverThrows() {
        assertNull(OctraRpcClient.extractResultOrNull(null));
        assertNull(OctraRpcClient.extractResultOrNull(new JSONObject()));
        assertNull(OctraRpcClient.extractResultOrNull(new JSONObject()));
        try {
            JSONObject ok = OctraRpcClient.extractResultOrNull(
                    new JSONObject("{\"result\":{\"x\":1}}"));
            assertEquals(1, ok.getInt("x"));
        } catch (Exception e) {
            fail("must not throw: " + e);
        }
    }
}
