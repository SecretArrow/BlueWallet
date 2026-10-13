package com.octopus.wallet;

import java.util.Locale;

/**
 * Pure favicon URL helpers (no Android imports — safe on the JVM so the Startpage policy is
 * unit-testable without Robolectric).
 */
public final class FaviconUrls {

  private FaviconUrls() {}

  /**
   * Resolves the classic {@code scheme://host/favicon.ico} address for an http/https page URL.
   * Returns "" for anything else (internal schemes, malformed input, empty host) — callers fall
   * back to the letter avatar.
   */
  public static String faviconUrlFor(String pageUrl) {
    if (pageUrl == null) {
      return "";
    }
    String t = pageUrl.trim();
    if (t.isEmpty()) {
      return "";
    }
    String low = t.toLowerCase(Locale.US);
    String scheme;
    if (low.startsWith("https://")) {
      scheme = "https";
    } else if (low.startsWith("http://")) {
      scheme = "http";
    } else {
      return "";
    }
    String host = hostOf(t);
    if (host.isEmpty()) {
      return "";
    }
    return scheme + "://" + host + "/favicon.ico";
  }

  /**
   * Extracts the bare host (no userinfo, no port) from an http/https URL using manual {@code
   * indexOf} parsing. Returns "" for anything else.
   */
  public static String hostOf(String pageUrl) {
    if (pageUrl == null) {
      return "";
    }
    String t = pageUrl.trim();
    String low = t.toLowerCase(Locale.US);
    if (!low.startsWith("http://") && !low.startsWith("https://")) {
      return "";
    }
    int schemeEnd = t.indexOf("://");
    if (schemeEnd < 0) {
      return "";
    }
    int start = schemeEnd + 3;
    if (start >= t.length()) {
      return "";
    }
    int end = t.length();
    for (int i = start; i < t.length(); i++) {
      char c = t.charAt(i);
      if (c == '/' || c == '?' || c == '#') {
        end = i;
        break;
      }
    }
    String host = t.substring(start, end).trim();
    if (host.isEmpty()) {
      return "";
    }
    // Drop userinfo (user:pass@host) — never part of the site identity.
    int at = host.lastIndexOf('@');
    if (at >= 0) {
      host = host.substring(at + 1).trim();
    }
    // Drop a trailing port, but keep IPv6 bracket contents intact.
    if (host.startsWith("[")) {
      int close = host.indexOf(']');
      if (close < 0) {
        return "";
      }
      host = host.substring(0, close + 1);
    } else {
      int colon = host.indexOf(':');
      if (colon >= 0) {
        host = host.substring(0, colon).trim();
      }
    }
    return host;
  }
}
