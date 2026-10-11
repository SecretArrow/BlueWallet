package com.octopus.wallet;

import android.content.Context;import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Per-origin dApp sessions. The permission itself persists in {@link
 * DappOriginStore} (so revoke in {@code DappOriginsActivity} /
 * {@code PermissionsCenter} survives restarts); the live address + scopes live
 * here in memory, keyed by normalized host.
 */
public final class DappSessionManager {

    /** Live session for one origin host. */
    public static final class Session {
        public final String host;
        public final String address;
        public final List<String> permissions;
        public final long connectedAt;

        Session(String host, String address, List<String> permissions, long connectedAt) {
            this.host = host;
            this.address = address == null ? "" : address;
            this.permissions = permissions == null
                    ? Collections.singletonList("accounts")
                    : Collections.unmodifiableList(new ArrayList<>(permissions));
            this.connectedAt = connectedAt;
        }
    }

    private final Map<String, Session> sessions = new HashMap<>();

    /** Normalized host for a page URL, or "" when unparseable. */
    public static String hostOf(String url) {
        if (url == null) return "";
        try {
            // java.net.URI (not android.net.Uri) so this stays pure-JVM testable.
            java.net.URI parsed = new java.net.URI(url.trim());
            String host = parsed.getHost();
            if (host == null) return "";
            return DappOriginStore.normalizeHost(host);
        } catch (Exception e) {
            return "";
        }
    }

    public synchronized void connect(String url, String address, List<String> permissions) {
        String host = hostOf(url);
        if (host.isEmpty() || address == null || address.isEmpty()) return;
        sessions.put(host, new Session(host, address,
                permissions == null || permissions.isEmpty()
                        ? Collections.singletonList("accounts") : permissions,
                System.currentTimeMillis()));
    }

    public synchronized boolean isConnected(String url) {
        String host = hostOf(url);
        if (host.isEmpty()) return false;
        Session s = sessions.get(host);
        return s != null && !s.address.isEmpty();
    }

    public synchronized String addressFor(String url) {
        String host = hostOf(url);
        Session s = sessions.get(host);
        return s == null ? "" : s.address;
    }

    public synchronized List<String> permissionsFor(String url) {
        String host = hostOf(url);
        Session s = sessions.get(host);
        if (s == null) return Collections.singletonList("accounts");
        return s.permissions;
    }

    public synchronized void disconnect(String url) {
        sessions.remove(hostOf(url));
    }

    public synchronized void disconnectAll() {
        sessions.clear();
    }

    /**
     * Revoke an origin completely: drop the live session and remove the
     * persisted allowlist entry so the next visit asks again.
     */
    public synchronized void revoke(Context context, String hostOrUrl) {
        String host = DappOriginStore.normalizeHost(hostOrUrl);
        sessions.remove(host);
        if (context != null && !host.isEmpty()) {
            DappOriginStore.removeOrigin(context, host);
        }
    }

    public synchronized int liveCount() {
        return sessions.size();
    }
}
