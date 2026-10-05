package com.octopus.wallet;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

import org.junit.Test;

/**
 * Pure-JVM tests for network profile helpers (no Context needed).
 */
public class NodeProfileStoreTest {

    private static List<NodeProfileStore.NodeProfile> list(String... names) {
        List<NodeProfileStore.NodeProfile> out = new ArrayList<>();
        for (String n : names) {
            out.add(new NodeProfileStore.NodeProfile(n, "https://x", ""));
        }
        return out;
    }

    @Test
    public void sanitizeName_stripsAndTrims() {
        assertEquals("My Node 1", NodeProfileStore.sanitizeName("  My Node!@# 1  "));
        assertEquals("", NodeProfileStore.sanitizeName(null));
        assertEquals("", NodeProfileStore.sanitizeName("!!!"));
        assertEquals("a-b_c", NodeProfileStore.sanitizeName("a-b_c"));
    }

    @Test
    public void uniqueName_dedupes() {
        assertEquals("X", NodeProfileStore.uniqueName(list(), "X"));
        assertEquals("X 2", NodeProfileStore.uniqueName(list("X"), "X"));
        assertEquals("X 3", NodeProfileStore.uniqueName(list("X", "X 2"), "X"));
        assertEquals("Y", NodeProfileStore.uniqueName(list("X", "X 2"), "Y"));
    }

    @Test
    public void findByName_nullSafe() {
        assertNull(NodeProfileStore.findByName(null, "X"));
        assertNull(NodeProfileStore.findByName(list("X"), null));
        assertNull(NodeProfileStore.findByName(list("X"), "Y"));
        assertEquals("X", NodeProfileStore.findByName(list("X"), "X").name);
        List<NodeProfileStore.NodeProfile> withNull =
                new ArrayList<>(Arrays.asList(null, list("X").get(0)));
        assertEquals("X", NodeProfileStore.findByName(withNull, "X").name);
    }
}
