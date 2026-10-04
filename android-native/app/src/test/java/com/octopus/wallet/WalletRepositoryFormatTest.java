package com.octopus.wallet;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

/**
 * Pure-JVM tests for OCT display formatting (integer microcoins only —
 * no floating point anywhere near money).
 */
public class WalletRepositoryFormatTest {

    @Test
    public void formatOct_zeroAndOne() {
        assertEquals("0", WalletRepository.formatOct(0L));
        assertEquals("0.000001", WalletRepository.formatOct(1L));
    }

    @Test
    public void formatOct_wholeCoins() {
        assertEquals("1", WalletRepository.formatOct(1_000_000L));
        assertEquals("42", WalletRepository.formatOct(42_000_000L));
    }

    @Test
    public void formatOct_fractions() {
        assertEquals("1.5", WalletRepository.formatOct(1_500_000L));
        assertEquals("1.234567", WalletRepository.formatOct(1_234_567L));
        assertEquals("0.1", WalletRepository.formatOct(100_000L));
    }

    @Test
    public void formatOct_largeValuesStayPlain() {
        // Long.MAX_VALUE microcoins must not render in scientific notation.
        assertEquals("9223372036854.775807", WalletRepository.formatOct(Long.MAX_VALUE));
    }
}
