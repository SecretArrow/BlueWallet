package com.octopus.wallet;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.fail;

import org.junit.Test;

/**
 * Pure-JVM tests for transaction input validation.
 */
public class TxInputValidatorTest {

    @Test
    public void requireAmountRaw_acceptsPositive() {
        assertEquals(1L, TxInputValidator.requireAmountRaw("1"));
        assertEquals(1_000_000L, TxInputValidator.requireAmountRaw("  1000000  "));
        assertEquals(Long.MAX_VALUE, TxInputValidator.requireAmountRaw(String.valueOf(Long.MAX_VALUE)));
    }

    @Test
    public void requireAmountRaw_rejectsMissingMalformedNonPositive() {
        for (String bad : new String[]{null, "", "   ", "abc", "1.5", "0", "-5", "99999999999999999999999"}) {
            try {
                TxInputValidator.requireAmountRaw(bad);
                fail("expected IllegalArgumentException for: " + bad);
            } catch (IllegalArgumentException e) {
                // Message must name the problem, never be blank.
                if (e.getMessage() == null || e.getMessage().isEmpty()) {
                    fail("empty message for: " + bad);
                }
            }
        }
    }

    @Test
    public void requireRecipient_trimsAndRejectsBlank() {
        assertEquals("octABC", TxInputValidator.requireRecipient("  octABC  "));
        for (String bad : new String[]{null, "", "   "}) {
            try {
                TxInputValidator.requireRecipient(bad);
                fail("expected IllegalArgumentException");
            } catch (IllegalArgumentException expected) {
            }
        }
    }
}
