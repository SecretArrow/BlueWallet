package com.octopus.wallet;

import static org.junit.Assert.assertEquals;

import org.json.JSONObject;
import org.junit.Test;

/**
 * Pure-JVM tests for nonce selection and fee parsing (no network).
 */
public class WalletRepositoryNonceFeeTest {

    // ── selectNonce ─────────────────────────────────────────────────────

    @Test
    public void selectNonce_prefersPendingNonce() throws Exception {
        JSONObject bal = new JSONObject("{\"nonce\":5,\"pending_nonce\":8}");
        assertEquals(8, WalletRepository.selectNonce(bal, 0));
    }

    @Test
    public void selectNonce_fallsBackToNonce() throws Exception {
        assertEquals(5, WalletRepository.selectNonce(new JSONObject("{\"nonce\":5}"), 0));
    }

    @Test
    public void selectNonce_missingYieldsFallback() throws Exception {
        assertEquals(0, WalletRepository.selectNonce(new JSONObject("{}"), 0));
        assertEquals(7, WalletRepository.selectNonce(new JSONObject("{}"), 7));
        assertEquals(0, WalletRepository.selectNonce(null, 0));
    }

    @Test
    public void selectNonce_acceptsNumericStrings() throws Exception {
        assertEquals(9, WalletRepository.selectNonce(
                new JSONObject("{\"pending_nonce\":\"9\"}"), 0));
        assertEquals(4, WalletRepository.selectNonce(
                new JSONObject("{\"nonce\":\"4\"}"), 0));
    }

    @Test
    public void selectNonce_rejectsNegativeAndGarbage() throws Exception {
        assertEquals(0, WalletRepository.selectNonce(
                new JSONObject("{\"nonce\":-3}"), 0));
        assertEquals(0, WalletRepository.selectNonce(
                new JSONObject("{\"nonce\":\"abc\"}"), 0));
        assertEquals(0, WalletRepository.selectNonce(
                new JSONObject("{\"nonce\":null}"), 0));
    }

    @Test
    public void selectNonce_clampsHugeValues() throws Exception {
        assertEquals(Integer.MAX_VALUE, WalletRepository.selectNonce(
                new JSONObject("{\"nonce\":9999999999999}"), 0));
    }

    // ── readLongField ───────────────────────────────────────────────────

    @Test
    public void readLongField_shapes() throws Exception {
        JSONObject o = new JSONObject("{\"a\":5,\"b\":\"42\",\"c\":null}");
        assertEquals(5L, WalletRepository.readLongField(o, "a", -1L));
        assertEquals(42L, WalletRepository.readLongField(o, "b", -1L));
        assertEquals(-1L, WalletRepository.readLongField(o, "c", -1L));
        assertEquals(-1L, WalletRepository.readLongField(o, "missing", -1L));
        assertEquals(-1L, WalletRepository.readLongField(null, "a", -1L));
    }

    // ── selectFee ───────────────────────────────────────────────────────

    @Test
    public void selectFee_validBucket() throws Exception {
        JSONObject root = new JSONObject(
                "{\"standard\":{\"recommended\":\"1500\",\"minimum\":\"1000\"}}");
        assertEquals(1500L, WalletRepository.selectFee(root, "standard", 1000L));
    }

    @Test
    public void selectFee_fallbacks() throws Exception {
        JSONObject root = new JSONObject(
                "{\"standard\":{\"recommended\":\"1500\"}}");
        // Missing category.
        assertEquals(1000L, WalletRepository.selectFee(root, "stealth", 1000L));
        // Zero / negative / garbage recommended.
        assertEquals(1000L, WalletRepository.selectFee(
                new JSONObject("{\"standard\":{\"recommended\":\"0\"}}"), "standard", 1000L));
        assertEquals(1000L, WalletRepository.selectFee(
                new JSONObject("{\"standard\":{\"recommended\":\"-5\"}}"), "standard", 1000L));
        assertEquals(1000L, WalletRepository.selectFee(
                new JSONObject("{\"standard\":{\"recommended\":\"lots\"}}"), "standard", 1000L));
        assertEquals(1000L, WalletRepository.selectFee(
                new JSONObject("{\"standard\":{}}"), "standard", 1000L));
        // Null root / category.
        assertEquals(1000L, WalletRepository.selectFee(null, "standard", 1000L));
        assertEquals(1000L, WalletRepository.selectFee(root, null, 1000L));
    }
}
