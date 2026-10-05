package com.octopus.wallet;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

/**
 * Pure-JVM tests for token formatting and session expiry.
 */
public class DisplayFormatTest {

    @Test
    public void tokenFormat_basic() {
        assertEquals("0", TokenFormat.format(null, 6));
        assertEquals("0", TokenFormat.format("", 6));
        assertEquals("0", TokenFormat.format("0", 6));
        assertEquals("1", TokenFormat.format("1000000", 6));
        assertEquals("1.5", TokenFormat.format("1500000", 6));
        assertEquals("1.234567", TokenFormat.format("1234567", 6));
        assertEquals("42", TokenFormat.format("42", 0));
    }

    @Test
    public void tokenFormat_outOfRangeDecimalsRenderRaw() {
        // Malicious/absurd decimals must not OOM — render raw instead.
        assertEquals("123", TokenFormat.format("123", -1));
        assertEquals("123", TokenFormat.format("123", 37));
        assertEquals("123", TokenFormat.format("123", 1000000));
        assertEquals("1", TokenFormat.format("1000000000000000000000000000000000000", 36));
    }

    @Test
    public void tokenFormat_garbageRendersRaw() {
        assertEquals("abc", TokenFormat.format("abc", 6));
        assertEquals("1.5.2", TokenFormat.format("1.5.2", 6));
    }

    @Test
    public void sessionExpiry_matrix() {
        long now = 1_700_000_000_000L;
        // Disabled → never lock.
        assertEquals(false, SessionLockActivity.isExpiredAt(now - 1_000_000L, 0, now));
        assertEquals(false, SessionLockActivity.isExpiredAt(now - 1_000_000L, -5, now));
        // Never recorded → force lock.
        assertEquals(true, SessionLockActivity.isExpiredAt(0L, 5, now));
        assertEquals(true, SessionLockActivity.isExpiredAt(-1L, 5, now));
        // Boundary: exactly at timeout locks, 1ms before does not.
        assertEquals(true, SessionLockActivity.isExpiredAt(now - 300_000L, 5, now));
        assertEquals(false, SessionLockActivity.isExpiredAt(now - 299_999L, 5, now));
        // Clock moved backwards → fail open (no lock storm).
        assertEquals(false, SessionLockActivity.isExpiredAt(now + 60_000L, 5, now));
        // Huge minutes cannot overflow (long arithmetic).
        assertEquals(false, SessionLockActivity.isExpiredAt(now - 1000L, Integer.MAX_VALUE, now));
    }
}
