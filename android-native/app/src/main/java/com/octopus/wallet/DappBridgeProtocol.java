package com.octopus.wallet;

import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

/**
 * Wire registry for the in-app dApp bridge (`window.octra`).
 *
 * <p>Dual-stack: the legacy BlueWallet dialect ({@code octra_sendTransaction},
 * ...) keeps working, and RFC-O-1 aliases ({@code octra_requestAccounts},
 * ...) dispatch alongside it. Error codes follow RFC-O-1 (0xio SDK guide)
 * so third-party adapters auto-detect this wallet.</p>
 *
 * <p>Pure JVM — no Android framework. Unit-tested.</p>
 */
public final class DappBridgeProtocol {

    private DappBridgeProtocol() {
    }

    // ── RFC-O-1 error codes ──────────────────────────────────────────────

    /** No code attached (legacy path, message only). */
    public static final int NO_CODE = 0;
    /** User rejected the request. */
    public static final int USER_REJECTED = 4001;
    /** Not connected / locked / unauthorized. */
    public static final int UNAUTHORIZED = 4100;
    /** Unknown method. */
    public static final int UNSUPPORTED_METHOD = 4200;
    /** Provider disconnected. */
    public static final int DISCONNECTED = 4900;
    /** Node/network failure. */
    public static final int NETWORK_UNAVAILABLE = 4901;

    // ── Methods ──────────────────────────────────────────────────────────
    //
    // Legacy dialect (existing clients) + RFC-O-1 aliases (new). Both lists
    // below form the complete wire surface — keep them in sync with
    // DappBrowserActivity.handleDappRequest.

    /** Legacy read methods. */
    public static final Set<String> LEGACY_METHODS = new HashSet<>(Arrays.asList(
            "octra_accounts",
            "octra_chainId",
            "octra_getBalance",
            "octra_sendTransaction",
            "octra_callContract",
            "octra_callView"
    ));

    /** RFC-O-1 alias: approval-gated account list. */
    public static final String REQUEST_ACCOUNTS = "octra_requestAccounts";
    /** RFC-O-1 alias: PVAC encrypted-balance cipher for the active wallet. */
    public static final String GET_ENCRYPTED_BALANCE = "octra_getEncryptedBalance";

    /** RFC-O-1 method names answered by the bridge. */
    public static final Set<String> RFC_METHODS = new HashSet<>(Arrays.asList(
            REQUEST_ACCOUNTS,
            GET_ENCRYPTED_BALANCE
    ));

    /** Trim + null-guard a raw method name from JS. */
    public static String canonicalize(String method) {
        return method == null ? "" : method.trim();
    }

    /** True when the bridge dispatches this method (either dialect). */
    public static boolean isSupported(String method) {
        String m = canonicalize(method);
        return LEGACY_METHODS.contains(m) || RFC_METHODS.contains(m);
    }
}
