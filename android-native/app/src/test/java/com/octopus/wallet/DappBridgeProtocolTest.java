package com.octopus.wallet;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

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
    public void isSupported_coversThirdPartyReads() {
        // 0xio OctraProviderAdapter: connect reads + session calls.
        for (String m : new String[]{"octra_networkInfo", "octra_permissions",
                "disconnect", "getBalance", "getPublicKey",
                "octra_sendContractTransaction", "octra_switchNetwork"}) {
            assertTrue("expected supported: " + m, DappBridgeProtocol.isSupported(m));
        }
        // View/submit share octra_callContract (shape-dispatched downstream).
        assertTrue(DappBridgeProtocol.isSupported("octra_callContract"));
    }

    @Test
    public void isKnownUnsupported_namesUnservedMethods() {
        // Sign-only split, message signing, FHE-private primitives: recognised
        // so the bridge rejects them explicitly instead of "unknown method".
        for (String m : new String[]{"octra_signTransaction", "octra_submitTransaction",
                "octra_signMessage", "octra_encryptBalance", "octra_decryptBalance",
                "octra_sendPrivateTransfer", "octra_claimStealth",
                "octra_getPrivateCapabilities", "octra_getPrivateBalance",
                "octra_encryptValue", "octra_decryptValue", "octra_makeZeroProof",
                "octra_makeRangeProof", "octra_registerPrivateViewKey",
                "octra_sendContractTransactionSequence", "octra_submitBatch"}) {
            assertTrue("expected known-unsupported: " + m,
                    DappBridgeProtocol.isKnownUnsupported(m));
            assertFalse("must not dispatch: " + m, DappBridgeProtocol.isSupported(m));
        }
        // Genuinely unknown names are neither.
        assertFalse(DappBridgeProtocol.isKnownUnsupported("octra_broadcast"));
        assertFalse(DappBridgeProtocol.isKnownUnsupported(null));
        assertTrue(DappBridgeProtocol.isKnownUnsupported("  octra_signMessage  "));
    }

    @Test
    public void extractRequestedPermissions_defaultsSafely() {
        assertEquals(java.util.Collections.singletonList("accounts"),
                DappBridgeProtocol.extractRequestedPermissions(null));
        assertEquals(java.util.Collections.singletonList("accounts"),
                DappBridgeProtocol.extractRequestedPermissions(""));
        assertEquals(java.util.Collections.singletonList("accounts"),
                DappBridgeProtocol.extractRequestedPermissions("[]"));
        assertEquals(java.util.Collections.singletonList("accounts"),
                DappBridgeProtocol.extractRequestedPermissions("[{\"other\":1}]"));
        assertEquals(java.util.Collections.singletonList("accounts"),
                DappBridgeProtocol.extractRequestedPermissions("not json"));
        java.util.List<String> got = DappBridgeProtocol.extractRequestedPermissions(
                "[{\"permissions\":[\"accounts\",\"public_transactions\",\"accounts\",\" \"]}]");
        assertEquals(java.util.Arrays.asList("accounts", "public_transactions"), got);
    }

    @Test
    public void asTxObject_acceptsBothShapes() throws Exception {
        // Legacy array form.
        assertEquals("octX",
                DappBridgeProtocol.asTxObject("[{\"to\":\"octX\",\"amount\":\"1\"}]")
                        .getString("to"));
        // Third-party bare-object form.
        assertEquals("octY",
                DappBridgeProtocol.asTxObject("{\"to\":\"octY\",\"amount\":\"2\"}")
                        .getString("to"));
        // Rejections name the problem.
        for (String bad : new String[]{null, "", "[]", "[42]", "42", "\"s\""}) {
            try {
                DappBridgeProtocol.asTxObject(bad);
                fail("expected JSONException for: " + bad);
            } catch (org.json.JSONException e) {
                assertTrue(e.getMessage().contains("params"));
            }
        }
    }

    @Test
    public void resolveTxAmount_exactArithmeticOnly() throws Exception {
        assertEquals("10500000", DappBridgeProtocol.resolveTxAmount(
                new org.json.JSONObject("{\"amount\":\"10500000\"}")));
        assertEquals("10500000", DappBridgeProtocol.resolveTxAmount(
                new org.json.JSONObject("{\"amountOct\":\"10.5\"}")));
        assertEquals("0", DappBridgeProtocol.resolveTxAmount(
                new org.json.JSONObject("{\"amount\":\"000\"}")));
        for (String bad : new String[]{
                "{\"amount\":\"1\",\"amountOct\":\"1\"}",
                "{}",
                "{\"amount\":\"-5\"}",
                "{\"amount\":\"1.5\"}",
                "{\"amountOct\":\"0.30000000000000004\"}",
                "{\"amountOct\":\"abc\"}",
                "{\"amountOct\":\"1.2345678\"}"}) {
            try {
                DappBridgeProtocol.resolveTxAmount(new org.json.JSONObject(bad));
                fail("expected JSONException for: " + bad);
            } catch (org.json.JSONException e) {
                // Expected — message names the violated rule.
                assertFalse(e.getMessage().isEmpty());
            }
        }
    }

    @Test
    public void octToMicro_convertsExactly() throws Exception {
        assertEquals("1", DappBridgeProtocol.octToMicro("0.000001"));
        assertEquals("2000000", DappBridgeProtocol.octToMicro("2"));
        assertEquals("0", DappBridgeProtocol.octToMicro("0.000000"));
    }

    @Test
    public void isViewCall_splitsByAttachedValue() throws Exception {
        // 0xio view: no value attached.
        assertTrue(DappBridgeProtocol.isViewCall(
                new org.json.JSONObject("{\"contract\":\"c\",\"method\":\"m\",\"params\":[]}")));
        assertTrue(DappBridgeProtocol.isViewCall(
                new org.json.JSONObject(
                        "{\"contract\":\"c\",\"method\":\"m\",\"params\":[],\"caller\":\"x\"}")));
        // Submissions always carry a value (even "0").
        assertFalse(DappBridgeProtocol.isViewCall(
                new org.json.JSONObject("{\"contract\":\"c\",\"method\":\"m\",\"amount\":\"0\"}")));
        assertFalse(DappBridgeProtocol.isViewCall(
                new org.json.JSONObject("{\"contract\":\"c\",\"method\":\"m\",\"ou\":\"10000\"}")));
        assertFalse(DappBridgeProtocol.isViewCall(null));
    }

    @Test
    public void acceptedSubmitJson_preservesRawAndAddsAccepted() throws Exception {
        org.json.JSONObject out = new org.json.JSONObject(DappBridgeProtocol
                .acceptedSubmitJson(new org.json.JSONObject("{\"tx_hash\":\"h1\"}")));
        assertEquals("h1", out.getString("hash"));
        assertEquals("h1", out.getString("tx_hash"));
        assertTrue(out.getBoolean("accepted"));
        assertTrue(out.getBoolean("success"));
        // Null/empty receipts stay bare: no fabricated acceptance.
        assertEquals("{}", DappBridgeProtocol.acceptedSubmitJson(null));
        assertEquals(
                "{}", DappBridgeProtocol.acceptedSubmitJson(new org.json.JSONObject()));
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
