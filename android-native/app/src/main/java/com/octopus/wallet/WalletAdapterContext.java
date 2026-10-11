package com.octopus.wallet;

import org.json.JSONObject;

import java.util.List;
import java.util.concurrent.ExecutorService;

/**
 * Services the browser exposes to a {@link WalletAdapter}. Implemented by
 * {@code DappBrowserActivity}; kept as an interface so adapters stay
 * unit-testable without Android.
 */
public interface WalletAdapterContext {

    /** Full current page URL (for origin derivation + display). */
    String getOrigin();

    /** Address of the connected session for the current origin, or "". */
    String getConnectedAddress();

    /** True when the current origin has an approved session. */
    boolean isConnected();

    /** Active wallet address (regardless of dApp session), or "". */
    String getWalletAddress();

    /** Base64 Ed25519 public key of the active wallet, or "". */
    String getWalletPublicKeyB64();

    /** Active node RPC URL (never empty; falls back to default). */
    String getRpcUrl();

    /** Active chain id, e.g. {@code octra-devnet-1}. */
    String getChainId();

    /** Network record served to third-party adapters. */
    JSONObject getNetworkInfo();

    /** Permissions granted to the current origin (never null). */
    List<String> getPermissions();

    /** Persist a newly approved session for the current origin. */
    void setSessionConnected(String address, List<String> permissions);

    /** Tear down the session for the current origin. */
    void clearSession();

    /** Answer a request (must run on the UI thread internally if needed). */
    void sendResult(int requestId, String resultJson);

    /** Answer a request with an error + RFC-O-1 code. */
    void sendError(int requestId, String error, int code);

    /** Answer with a plain error (code {@link DappBridgeProtocol#NO_CODE}). */
    default void sendError(int requestId, String error) {
        sendError(requestId, error, DappBridgeProtocol.NO_CODE);
    }

    /** True when the request was cancelled/destroyed and must not be answered. */
    boolean isCancelled(int requestId);

    /** False once the host Activity/WebView is gone (drop late callbacks). */
    boolean isAlive();

    /** Shared I/O pool for RPC / native work. */
    ExecutorService io();

    /** User approval for a sensitive action. Cancel/dismiss == deny. */
    void requestApproval(String title, String message, ApprovalCallback callback);

    /** Approval continuation. */
    interface ApprovalCallback {
        void onDecision(boolean approved);
    }
}
