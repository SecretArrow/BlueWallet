package com.octopus.wallet;

/**
 * Pure-JVM validation for transaction task inputs (no Android framework).
 *
 * <p>Fail-safe contract: invalid amounts or recipients throw with a specific
 * message instead of coercing to zero/empty (a zero-amount tx would burn fees
 * for nothing). All task runners treat these as task failure with a
 * user-visible notification.
 */
public final class TxInputValidator {

    private TxInputValidator() {
    }

    /**
     * Parse a raw amount string into microcoins.
     *
     * @throws IllegalArgumentException when missing, malformed or ≤ 0
     */
    public static long requireAmountRaw(String raw) {
        if (raw == null || raw.trim().isEmpty()) {
            throw new IllegalArgumentException("Amount is missing");
        }
        final long v;
        try {
            v = Long.parseLong(raw.trim());
        } catch (NumberFormatException e) {
            throw new IllegalArgumentException("Amount is not a number: '" + raw + "'", e);
        }
        if (v <= 0L) {
            throw new IllegalArgumentException("Amount must be greater than 0 (got " + v + ")");
        }
        return v;
    }

    /**
     * Validate a recipient address, returning the trimmed value.
     *
     * @throws IllegalArgumentException when missing or blank
     */
    public static String requireRecipient(String to) {
        if (to == null || to.trim().isEmpty()) {
            throw new IllegalArgumentException("Recipient address is missing");
        }
        return to.trim();
    }
}
