package com.octopus.wallet;

import android.net.Uri;

import java.util.Locale;

public final class UrlSecurityValidator {
    public static final String DEFAULT_RPC = "https://rpc.octrascan.io";
    public static final String DEFAULT_EXPLORER = "https://octrascan.io";

    public static final String DEVNET_RPC = "http://165.227.225.79:8080";
    public static final String DEVNET_EXPLORER = "https://devnet.octrascan.io";

    /** Mainnet endpoints per https://octrascan.io/docs.html */
    public static final String MAINNET_RPC = "https://rpc.octrascan.io";
    public static final String MAINNET_EXPLORER = "https://octrascan.io";

    private UrlSecurityValidator() {
    }

    public static String normalizeRpcUrl(String input) {
        return normalizeUrl(input, DEFAULT_RPC, false);
    }

    public static String normalizeExplorerUrl(String input) {
        return normalizeUrl(input, DEFAULT_EXPLORER, true);
    }

    public static boolean isValidRpcUrl(String input) {
        return isValidUrl(input, false);
    }

    public static boolean isValidExplorerUrl(String input) {
        return isValidUrl(input, true);
    }

    public static boolean isCleartextRpc(String rpcUrl) {
        Uri uri = parse(rpcUrl);
        if (uri == null) return false;
        String scheme = uri.getScheme() == null ? "" : uri.getScheme().toLowerCase(Locale.US);
        if (!"http".equals(scheme)) return false;
        String host = uri.getHost() == null ? "" : uri.getHost().toLowerCase(Locale.US);
        return !isLocalOrTrustedCleartextHost(host);
    }

    private static boolean isValidUrl(String input, boolean requireHttps) {
        String normalized = normalizeUrl(input, null, requireHttps);
        return normalized != null;
    }

    private static String normalizeUrl(String input, String fallback, boolean requireHttps) {
        String candidate = input == null ? "" : input.trim();
        if (candidate.isEmpty()) {
            candidate = fallback == null ? "" : fallback;
        }
        if (candidate.isEmpty()) {
            return null;
        }

        if (!candidate.contains("://")) {
            candidate = (requireHttps ? "https://" : "http://") + candidate;
        }

        Uri uri = parse(candidate);
        if (uri == null) {
            return null;
        }
        String scheme = uri.getScheme() == null ? "" : uri.getScheme().toLowerCase(Locale.US);
        String host = uri.getHost();
        if (host == null || host.trim().isEmpty()) {
            return null;
        }
        if (!"http".equals(scheme) && !"https".equals(scheme)) {
            return null;
        }
        if (requireHttps && !"https".equals(scheme)) {
            return null;
        }

        return uri.buildUpon().encodedPath(uri.getEncodedPath()).build().toString();
    }

    private static boolean isLocalOrTrustedCleartextHost(String host) {
        if (host == null || host.isEmpty()) return false;
        if ("localhost".equals(host) || "127.0.0.1".equals(host)) {
            return true;
        }
        // Devnet node IP
        if ("165.227.225.79".equals(host)) return true;
        // Mainnet and devnet explorers over HTTPS don't need cleartext exception,
        // but include known hosts for completeness.
        return false;
    }

    private static Uri parse(String input) {
        try {
            return Uri.parse(input);
        } catch (Exception e) {
            return null;
        }
    }

}
