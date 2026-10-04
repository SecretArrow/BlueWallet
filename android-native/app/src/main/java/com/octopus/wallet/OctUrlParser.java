package com.octopus.wallet;

/**
 * Pure-JVM helpers for the native {@code oct://} circle protocol.
 *
 * <p>Octra circle URLs look like {@code oct://<circleId>/<path>} (a bare
 * circle ID defaults to {@code /index.html}, mirroring the local web server
 * gateway). Parsing is manual — never {@code android.net.Uri} — so base58
 * circle IDs keep their case, and the class stays unit-testable without
 * Robolectric.
 */
public final class OctUrlParser {

    public static final String OCT_SCHEME = "oct://";

    private OctUrlParser() {
    }

    public static boolean isOctUrl(String url) {
        return url != null && url.regionMatches(true, 0, OCT_SCHEME, 0, OCT_SCHEME.length());
    }

    /**
     * Split an oct:// URL into {@code [circleId, path]}.
     * Query strings and fragments are stripped.
     */
    public static String[] parseOctUrl(String url) {
        String rest = url.substring(OCT_SCHEME.length());
        int cut = rest.length();
        for (int i = 0; i < rest.length(); i++) {
            char c = rest.charAt(i);
            if (c == '?' || c == '#') {
                cut = i;
                break;
            }
        }
        rest = rest.substring(0, cut);
        int idx = rest.indexOf('/');
        if (idx == -1) {
            return new String[]{rest, "/index.html"};
        }
        String path = rest.substring(idx);
        if (path.isEmpty() || "/".equals(path)) {
            path = "/index.html";
        }
        return new String[]{rest.substring(0, idx), path};
    }

    /** MIME types safe to render inline as text in a WebView. */
    public static boolean isTextMime(String mime) {
        return mime.startsWith("text/") || mime.contains("javascript")
                || mime.contains("json") || mime.endsWith("+xml")
                || mime.equals("image/svg+xml");
    }
}
