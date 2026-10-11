package com.octopus.wallet;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Registry of {@link WalletAdapter}s. The Octra adapter is registered by
 * default; new networks/protocols call {@link #register} at startup.
 */
public final class AdapterRegistry {

    private static final List<WalletAdapter> ADAPTERS = new ArrayList<>();

    static {
        ADAPTERS.add(new OctraWalletAdapter());
    }

    private AdapterRegistry() {
    }

    public static synchronized void register(WalletAdapter adapter) {
        if (adapter == null) return;
        for (WalletAdapter a : ADAPTERS) {
            if (a.getAdapterId().equals(adapter.getAdapterId())) return;
        }
        ADAPTERS.add(adapter);
    }

    /** Adapter handling the raw (possibly aliased) method, or null. */
    public static synchronized WalletAdapter resolve(String method) {
        String canonical = DappBridgeProtocol.canonicalize(method);
        if (canonical.isEmpty()) return null;
        for (WalletAdapter a : ADAPTERS) {
            try {
                if (a.supports(canonical)) return a;
            } catch (Exception ignored) {
                // A misbehaving adapter must never break resolution.
            }
        }
        return null;
    }

    public static boolean isSupported(String method) {
        return resolve(method) != null || DappBridgeProtocol.isSupported(method);
    }

    public static synchronized List<WalletAdapter> snapshot() {
        return Collections.unmodifiableList(new ArrayList<>(ADAPTERS));
    }
}
