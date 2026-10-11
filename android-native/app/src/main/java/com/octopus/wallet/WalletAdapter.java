package com.octopus.wallet;

import java.util.Set;

/**
 * Modular dApp wallet adapter (plan.txt § dApp Wallet Adapter).
 *
 * <p>One adapter per network/protocol family. The in-app browser resolves the
 * canonical method name via {@link DappBridgeProtocol#canonicalize} and
 * dispatches to the first adapter whose {@link #supports} returns true, so new
 * networks/protocols plug in through {@link AdapterRegistry} without touching
 * the bridge.
 */
public interface WalletAdapter {

    /** Stable id, e.g. {@code "octra"}. */
    String getAdapterId();

    /** Canonical method names this adapter dispatches. */
    Set<String> getSupportedMethods();

    /** True when this adapter handles {@code canonicalMethod}. */
    boolean supports(String canonicalMethod);

    /**
     * Dispatch a request. Implementations must answer exactly once via {@code
     * ctx.sendResult} / {@code ctx.sendError} unless the request was
     * cancelled/destroyed (check {@code ctx.isCancelled(requestId)} before
     * answering late async work).
     *
     * @return true when dispatched (bridge skips its unsupported-method error)
     */
    boolean handle(WalletAdapterContext ctx, int requestId,
                   String canonicalMethod, String paramsJson);
}
