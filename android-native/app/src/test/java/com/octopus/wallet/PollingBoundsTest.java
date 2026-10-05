package com.octopus.wallet;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

/**
 * Pure-JVM tests for polling interval bounds.
 */
public class PollingBoundsTest {

    @Test
    public void clampInterval_bounds() {
        assertEquals(5000L, PollingSettingsStore.clampInterval(5000L));
        assertEquals(1000L, PollingSettingsStore.clampInterval(0L));
        assertEquals(1000L, PollingSettingsStore.clampInterval(-100L));
        assertEquals(86400000L, PollingSettingsStore.clampInterval(999999999L));
        assertEquals(86400000L, PollingSettingsStore.clampInterval(Long.MAX_VALUE));
    }

    @Test
    public void clampThreshold_fallsBackOutsideRange() {
        assertEquals(300000L, PollingSettingsStore.clampThreshold(300000L, 300000L));
        assertEquals(0L, PollingSettingsStore.clampThreshold(0L, 300000L));
        assertEquals(300000L, PollingSettingsStore.clampThreshold(-1L, 300000L));
        assertEquals(300000L,
                PollingSettingsStore.clampThreshold(604800001L, 300000L));
        assertEquals(604800000L,
                PollingSettingsStore.clampThreshold(604800000L, 300000L));
    }
}
