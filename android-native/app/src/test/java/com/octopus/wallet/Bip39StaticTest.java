package com.octopus.wallet;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.fail;

import org.junit.Test;

/**
 * Pure-JVM tests for BIP-39 helpers (no wordlist/Context needed —
 * normalization and path parsing are static).
 */
public class Bip39StaticTest {

    @Test
    public void normalize_collapsesWhitespaceAndLowercases() {
        assertEquals("abandon abandon about",
                Bip39.normalize("  Abandon\tABANDON\nabout  "));
        assertEquals("a b c", Bip39.normalize("a   b\t\tc"));
        assertEquals("", Bip39.normalize("   "));
    }

    @Test
    public void normalize_rejectsNull() {
        try {
            Bip39.normalize(null);
            fail("expected IllegalArgumentException");
        } catch (IllegalArgumentException expected) {
        }
    }

    @Test
    public void parsePath_standardPaths() {
        assertArrayEquals(new int[]{44, 540, 0, 0, 0},
                Bip39.parsePath("m/44'/540'/0'/0'/0'"));
        assertArrayEquals(new int[]{44, 0},
                Bip39.parsePath("M/44'/0"));
        assertArrayEquals(new int[]{7}, Bip39.parsePath("7"));
        assertArrayEquals(new int[]{7}, Bip39.parsePath("7'"));
        assertArrayEquals(new int[0], Bip39.parsePath("m"));
    }

    @Test
    public void parsePath_rejectsGarbage() {
        for (String bad : new String[]{"m//0", "m/abc", "m/-1", "m/1//2", ""}) {
            try {
                Bip39.parsePath(bad);
                fail("expected IllegalArgumentException for: '" + bad + "'");
            } catch (IllegalArgumentException expected) {
            }
        }
    }

    @Test
    public void isValidPin_matchesVerifierPolicy() {
        // Mirrors WalletPinVerifier: exactly 6 digits, nothing else.
        assertEquals(true, PinStore.isValidPin("123456"));
        assertEquals(false, PinStore.isValidPin(null));
        assertEquals(false, PinStore.isValidPin(""));
        assertEquals(false, PinStore.isValidPin("12345"));
        assertEquals(false, PinStore.isValidPin("1234567"));
        assertEquals(false, PinStore.isValidPin("12345a"));
        assertEquals(true, PinStore.isValidPin(" 123456 "));
    }
}
