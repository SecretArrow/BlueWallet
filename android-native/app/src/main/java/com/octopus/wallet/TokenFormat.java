package com.octopus.wallet;

/**
 * Pure-JVM token amount formatter (no Android framework).
 *
 * <p>Contract: empty/null → {@code "0"}; decimals outside 0..36 render raw
 * (a malicious token advertising absurd decimals would otherwise OOM the UI
 * thread in {@code BigDecimal.pow}); unparsable input renders raw; trailing
 * zeros stripped, never scientific notation.</p>
 */
public final class TokenFormat {

    /** Real token standards cap decimals at 18; 36 is a generous ceiling. */
    public static final int MAX_DECIMALS = 36;

    private TokenFormat() {
    }

    public static String format(String rawValue, int decimals) {
        if (rawValue == null || rawValue.isEmpty()) return "0";
        if (decimals < 0 || decimals > MAX_DECIMALS) return rawValue;
        try {
            java.math.BigDecimal raw = new java.math.BigDecimal(rawValue);
            java.math.BigDecimal divisor = java.math.BigDecimal.TEN.pow(decimals);
            java.math.BigDecimal formatted =
                    raw.divide(divisor, decimals, java.math.RoundingMode.DOWN);
            return formatted.stripTrailingZeros().toPlainString();
        } catch (Exception e) {
            return rawValue;
        }
    }
}
