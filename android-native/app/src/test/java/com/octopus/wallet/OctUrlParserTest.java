package com.octopus.wallet;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/**
 * Pure-JVM tests for the oct:// URL helpers (no Android framework needed).
 */
public class OctUrlParserTest {

    @Test
    public void isOctUrl_matchesCaseInsensitively() {
        assertTrue(OctUrlParser.isOctUrl("oct://abc123/index.html"));
        assertTrue(OctUrlParser.isOctUrl("OCT://abc123/"));
        assertTrue(OctUrlParser.isOctUrl("Oct://abc123"));
        assertFalse(OctUrlParser.isOctUrl("https://example.com"));
        assertFalse(OctUrlParser.isOctUrl("http://127.0.0.1:8420/oct/abc"));
        assertFalse(OctUrlParser.isOctUrl(null));
        assertFalse(OctUrlParser.isOctUrl(""));
    }

    @Test
    public void parseOctUrl_splitsCircleAndPath() {
        assertArrayEquals(new String[]{"myCircle", "/index.html"},
                OctUrlParser.parseOctUrl("oct://myCircle/index.html"));
        assertArrayEquals(new String[]{"abc", "/assets/app.js"},
                OctUrlParser.parseOctUrl("oct://abc/assets/app.js"));
    }

    @Test
    public void parseOctUrl_bareIdDefaultsToIndex() {
        assertArrayEquals(new String[]{"abc123", "/index.html"},
                OctUrlParser.parseOctUrl("oct://abc123"));
        assertArrayEquals(new String[]{"abc123", "/index.html"},
                OctUrlParser.parseOctUrl("oct://abc123/"));
    }

    @Test
    public void parseOctUrl_stripsQueryAndFragment() {
        assertArrayEquals(new String[]{"abc", "/page.html"},
                OctUrlParser.parseOctUrl("oct://abc/page.html?x=1#frag"));
    }

    @Test
    public void parseOctUrl_preservesBase58Case() {
        // Circle IDs are base58 — case must survive parsing.
        assertArrayEquals(new String[]{"octBjnQBicZs6iMwcRxrdzLYAzyVTi91KEiA8RGkVjco2w6", "/index.html"},
                OctUrlParser.parseOctUrl("oct://octBjnQBicZs6iMwcRxrdzLYAzyVTi91KEiA8RGkVjco2w6"));
    }

    @Test
    public void isTextMime_classifiesCorrectly() {
        assertTrue(OctUrlParser.isTextMime("text/html"));
        assertTrue(OctUrlParser.isTextMime("text/css"));
        assertTrue(OctUrlParser.isTextMime("application/javascript"));
        assertTrue(OctUrlParser.isTextMime("application/json"));
        assertTrue(OctUrlParser.isTextMime("image/svg+xml"));
        assertFalse(OctUrlParser.isTextMime("image/png"));
        assertFalse(OctUrlParser.isTextMime("application/octet-stream"));
        assertFalse(OctUrlParser.isTextMime("font/woff2"));
    }
}
