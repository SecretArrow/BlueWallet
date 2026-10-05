package com.octopus.wallet;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/**
 * Pure-JVM tests for stealth task status handling.
 */
public class StealthTaskStatusTest {

    @Test
    public void normalizeStatus_knownValues() {
        assertEquals("queued", StealthTaskManager.normalizeStatus("queued"));
        assertEquals("queued", StealthTaskManager.normalizeStatus("  QUEUED "));
        assertEquals("queued", StealthTaskManager.normalizeStatus(null));
        assertEquals("queued", StealthTaskManager.normalizeStatus(""));
        assertEquals("running", StealthTaskManager.normalizeStatus("running"));
        assertEquals("running", StealthTaskManager.normalizeStatus("pending"));
        assertEquals("success", StealthTaskManager.normalizeStatus("success"));
        assertEquals("success", StealthTaskManager.normalizeStatus("confirmed"));
        assertEquals("success", StealthTaskManager.normalizeStatus("done"));
        assertEquals("failed", StealthTaskManager.normalizeStatus("failed"));
        assertEquals("failed", StealthTaskManager.normalizeStatus("TIMEOUT"));
        assertEquals("failed", StealthTaskManager.normalizeStatus("invalid"));
    }

    @Test
    public void normalizeStatus_unfinishedIsNotSuccess() {
        // "unfinished" contains "finish" — must not classify as success.
        assertEquals("failed", StealthTaskManager.normalizeStatus("unfinished"));
    }

    @Test
    public void normalizeStatus_unknownFailsLoudly() {
        // Unknown statuses fail (retryable) instead of hanging as running.
        assertEquals("failed", StealthTaskManager.normalizeStatus("mystery-state"));
    }

    @Test
    public void activeFinishedPartition() {
        assertTrue(StealthTaskManager.isActiveStatus("queued"));
        assertTrue(StealthTaskManager.isActiveStatus("running"));
        assertFalse(StealthTaskManager.isActiveStatus("success"));
        assertFalse(StealthTaskManager.isActiveStatus("failed"));
        assertTrue(StealthTaskManager.isFinishedStatus("success"));
        assertTrue(StealthTaskManager.isFinishedStatus("failed"));
        assertFalse(StealthTaskManager.isFinishedStatus("running"));
    }

    @Test
    public void parseStepNumerator_shapes() {
        // Package-visible static backing heartbeat monotonicity.
        assertEquals(7, StealthTaskManager.parseStepNumerator("7/9"));
        assertEquals(3, StealthTaskManager.parseStepNumerator("3"));
        assertEquals(-1, StealthTaskManager.parseStepNumerator(null));
        assertEquals(-1, StealthTaskManager.parseStepNumerator(""));
        assertEquals(-1, StealthTaskManager.parseStepNumerator("x/y"));
    }
}
