package com.octopus.wallet;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

/** Pure-JVM tests for favicon URL resolution (fallback policy). */
public class FaviconUrlTest {

  @Test
  public void faviconUrlFor_httpsWithPath() {
    assertEquals(
        "https://devnet.octrascan.io/favicon.ico",
        FaviconUrls.faviconUrlFor("https://devnet.octrascan.io/tx/abc?x=1"));
    assertEquals(
        "https://Example.com/favicon.ico", FaviconUrls.faviconUrlFor("https://Example.com/a/b"));
  }

  @Test
  public void faviconUrlFor_httpRoot() {
    assertEquals("http://example.com/favicon.ico", FaviconUrls.faviconUrlFor("http://example.com"));
    assertEquals(
        "http://example.com/favicon.ico", FaviconUrls.faviconUrlFor("  http://example.com/  "));
  }

  @Test
  public void faviconUrlFor_stripsPortsAndUserinfo() {
    assertEquals(
        "https://example.com/favicon.ico",
        FaviconUrls.faviconUrlFor("https://example.com:8443/app"));
    assertEquals(
        "https://example.com/favicon.ico",
        FaviconUrls.faviconUrlFor("https://user:pass@example.com/app"));
  }

  @Test
  public void faviconUrlFor_rejectsNonHttpSchemes() {
    for (String url :
        new String[] {
          null,
          "",
          "   ",
          "ftp://example.com",
          "file:///sdcard/x.html",
          "about:blank",
          "chrome://newtab",
          "oct://circle123/index.html",
          "example.com",
          "example.com/favicon.ico",
        }) {
      assertEquals("must not resolve: " + url, "", FaviconUrls.faviconUrlFor(url));
    }
  }

  @Test
  public void faviconUrlFor_rejectsMalformedUrls() {
    assertEquals("", FaviconUrls.faviconUrlFor("https://"));
    assertEquals("", FaviconUrls.faviconUrlFor("http:///path"));
    assertEquals("", FaviconUrls.faviconUrlFor("https://?q=1"));
    assertEquals("", FaviconUrls.faviconUrlFor("not a url"));
  }

  @Test
  public void hostOf_extractsBareHost() {
    assertEquals("devnet.octrascan.io", FaviconUrls.hostOf("https://devnet.octrascan.io/a?b=1#f"));
    assertEquals("example.com", FaviconUrls.hostOf("http://user@example.com:8080/"));
    assertEquals("[::1]", FaviconUrls.hostOf("http://[::1]:8420/app"));
    assertEquals("", FaviconUrls.hostOf("oct://circle123"));
    assertEquals("", FaviconUrls.hostOf(null));
  }
}
