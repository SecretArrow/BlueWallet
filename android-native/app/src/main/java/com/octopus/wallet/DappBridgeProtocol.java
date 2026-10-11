package com.octopus.wallet;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
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

    // ── Third-party provider surface (0xio SDK OctraProviderAdapter) ──────
    //
    // Clean-room interface mapping (method names only — no third-party code
    // is vendored or copied): the adapter at @0xio/sdk drives
    // window.octra.request() with the names below. Served entries dispatch
    // in DappBrowserActivity.handleDappRequest; the known-unsupported list
    // is rejected EXPLICITLY (never silently) so dApps fail diagnosably.

    /** Reads + session calls the bridge answers for third-party adapters. */
    public static final Set<String> XIO_SERVED_METHODS = new HashSet<>(Arrays.asList(
            "octra_networkInfo",
            "octra_permissions",
            "disconnect",
            "getBalance",
            "getPublicKey",
            "octra_sendContractTransaction",
            "octra_switchNetwork"
    ));

    /**
     * Methods the bridge recognises but does not serve: sign-only submission
     * split (this wallet submits via its own approval — it never hands out
     * unsigned broadcasts), message signing, and FHE-private primitives.
     * Answered with UNSUPPORTED_METHOD naming the method.
     */
    public static final Set<String> KNOWN_UNSUPPORTED_METHODS = new HashSet<>(Arrays.asList(
            "octra_signTransaction",
            "octra_submitTransaction",
            "octra_signMessage",
            "octra_encryptBalance",
            "octra_decryptBalance",
            "octra_sendPrivateTransfer",
            "octra_claimStealth",
            "octra_getPrivateCapabilities",
            "octra_getPrivateBalance",
            "octra_encryptValue",
            "octra_decryptValue",
            "octra_makeZeroProof",
            "octra_makeRangeProof",
            "octra_registerPrivateViewKey",
            "octra_sendContractTransactionSequence",
            "octra_submitBatch",
            "wallet_signMessage",
            "wallet_signTypedData",
            "wallet_approveContract",
            "wallet_signContract",
            "wallet_signTransfer"
    ));

    // ── window.wallet surface (Orion-style high-level provider) ────────────
    //
    // Clean-room name mapping (no third-party code vendored or copied): the
    // injected `window.wallet` facade speaks these `wallet_*` names and the
    // bridge answers the read/session subset. Like the rest of this wallet,
    // signing stays approval-gated submit — the sign-only methods below are
    // recognised and refused, never silently dropped.

    /** Reads + session calls answered for the window.wallet facade. */
    public static final Set<String> WALLET_SERVED_METHODS = new HashSet<>(Arrays.asList(
            "wallet_connect",
            "wallet_disconnect",
            "wallet_getAccounts",
            "wallet_getAddress",
            "wallet_getBalance",
            "wallet_getNetwork",
            "wallet_getNetworkInfo",
            "wallet_getNetworks",
            "wallet_getChainId",
            "wallet_getPermissions",
            "wallet_ping"
    ));

    /** Orion-brand prefix; an alias for the matching wallet_* method. */
    public static final String ORION_PREFIX = "orion_wallet_";

    /**
     * Reduce a method name to its canonical form: trims, then folds the
     * {@code orion_wallet_} alias onto {@code wallet_*}. Unknown names pass
     * through unchanged and are rejected downstream.
     */
    public static String canonicalize(String method) {
        if (method == null) return "";
        String trimmed = method.trim();
        if (trimmed.startsWith(ORION_PREFIX)) {
            return "wallet_" + trimmed.substring(ORION_PREFIX.length());
        }
        return trimmed;
    }

    /** True when the bridge dispatches this method (any dialect). */
    public static boolean isSupported(String method) {
        String m = canonicalize(method);
        return LEGACY_METHODS.contains(m) || RFC_METHODS.contains(m)
                || XIO_SERVED_METHODS.contains(m) || WALLET_SERVED_METHODS.contains(m);
    }

    /** True for a recognised-but-unserved method (explicit reject, never silent). */
    public static boolean isKnownUnsupported(String method) {
        return KNOWN_UNSUPPORTED_METHODS.contains(canonicalize(method));
    }

    /**
     * Stable network id ("mainnet" or "devnet") for a chain id. Static so
     * JVM tests cover the mapping without Android.
     */
    public static String networkIdForChain(String chainId) {
        return chainId != null && chainId.contains("mainnet") ? "mainnet" : "devnet";
    }

    /**
     * Liveness record for {@code wallet_ping}: answers without touching
     * wallet state, opening a popup, or mutating the session it observes.
     */
    public static JSONObject buildPing(boolean connected, boolean locked,
                                       String origin, long tsMs) throws JSONException {
        JSONObject o = new JSONObject();
        o.put("pong", true);
        o.put("v", 1);
        o.put("connected", connected);
        o.put("locked", locked);
        JSONArray caps = new JSONArray();
        caps.put("ping");
        caps.put("events");
        o.put("capabilities", caps);
        o.put("origin", origin != null ? origin : "");
        o.put("ts", tsMs);
        return o;
    }

    // ── Pure param helpers (third-party object forms) ─────────────────────
    //
    // Third-party adapters send a BARE OBJECT ({to, amount, ...}) where the
    // legacy dialect sends a single-element array ([{...}]). Everything below
    // is static + side-effect free so JVM tests cover it without Android.

    /**
     * Permissions the page asked for ({@code [{permissions: [...]}]}), or
     * {@code ["accounts"]} when nothing parseable was asked. Never throws: a
     * malformed request still gets the default, and the approval dialog —
     * not this parser — is the security boundary.
     */
    public static List<String> extractRequestedPermissions(String paramsJson) {
        List<String> fallback = new ArrayList<>(Collections.singletonList("accounts"));
        if (paramsJson == null || paramsJson.isEmpty()) return fallback;
        try {
            JSONArray params = new JSONArray(paramsJson);
            if (params.length() == 0) return fallback;
            JSONObject first = params.optJSONObject(0);
            if (first == null) return fallback;
            JSONArray perms = first.optJSONArray("permissions");
            if (perms == null || perms.length() == 0) return fallback;
            List<String> out = new ArrayList<>();
            for (int i = 0; i < perms.length(); i++) {
                String p = perms.optString(i, "").trim();
                if (!p.isEmpty() && !out.contains(p)) out.add(p);
            }
            return out.isEmpty() ? fallback : out;
        } catch (JSONException e) {
            return fallback;
        }
    }

    /**
     * The single transaction object out of either param shape: a legacy
     * {@code [{...}]} array or a bare {@code {...}} object. Throws
     * JSONException naming the problem (never returns null).
     */
    public static JSONObject asTxObject(String paramsJson) throws JSONException {
        if (paramsJson == null || paramsJson.trim().isEmpty()) {
            throw new JSONException("empty params");
        }
        String t = paramsJson.trim();
        try {
            if (t.startsWith("[")) {
                JSONArray params = new JSONArray(t);
                if (params.length() == 0) throw new JSONException("empty params array");
                JSONObject tx = params.optJSONObject(0);
                if (tx == null) throw new JSONException("params[0] must be an object");
                return tx;
            }
            return new JSONObject(t);
        } catch (JSONException e) {
            throw new JSONException("params must be an object or a single-element array: "
                    + e.getMessage());
        }
    }

    /**
     * Exactly one of {@code amount} (raw micro-OCT) / {@code amountOct}
     * (decimal OCT, at most 6 decimals). Floats that cannot be written
     * exactly are rejected, never rounded.
     */
    public static String resolveTxAmount(JSONObject tx) throws JSONException {
        boolean hasRaw = tx.has("amount") && !tx.isNull("amount")
                && !tx.optString("amount", "").isEmpty();
        boolean hasOct = tx.has("amountOct") && !tx.isNull("amountOct")
                && !tx.optString("amountOct", "").isEmpty();
        if (hasRaw && hasOct) {
            throw new JSONException("pass either amount or amountOct, never both");
        }
        if (hasRaw) {
            String s = tx.optString("amount", "").trim().replaceFirst("^0+(?=\\d)", "");
            if (!s.matches("\\d+")) {
                throw new JSONException("amount must be a non-negative integer string");
            }
            return s;
        }
        if (hasOct) return octToMicro(tx.optString("amountOct", "").trim());
        throw new JSONException("missing amount or amountOct");
    }

    /**
     * Exact OCT → micro-OCT decimal conversion (max 6 decimals, no floats).
     * Throws JSONException on anything inexact or malformed.
     */
    public static String octToMicro(String input) throws JSONException {
        if (input == null || input.trim().isEmpty()) {
            throw new JSONException("empty amountOct");
        }
        String t = input.trim();
        int dot = t.indexOf('.');
        String whole = dot < 0 ? t : t.substring(0, dot);
        String frac = dot < 0 ? "" : t.substring(dot + 1);
        if (!whole.matches("\\d+") || !frac.matches("\\d*") || frac.length() > 6) {
            throw new JSONException("amountOct must be a decimal with at most 6 places");
        }
        while (frac.length() < 6) frac += "0";
        String micro = (whole.replaceFirst("^0+(?=\\d)", "") + frac)
                .replaceFirst("^0+(?=\\d)", "");
        return micro.isEmpty() ? "0" : micro;
    }

    /**
     * True for a read-only view call: an object WITHOUT any attached value.
     * Third-party adapters send views as {contract, method, params, caller?};
     * submissions always carry amount (and usually ou).
     */
    public static boolean isViewCall(JSONObject o) {
        return o != null && !o.has("amount") && !o.has("ou");
    }

    /**
     * Merge a raw submit receipt with the fields third-party adapters read
     * ({@code hash}, {@code accepted}). Legacy readers keep working: the raw
     * keys ({@code tx_hash}, …) are preserved untouched.
     */
    public static String acceptedSubmitJson(JSONObject result) {
        // A null/empty receipt is returned bare ("{}"): fabricating
        // accepted:true for a receipt that does not exist would report a
        // success that never happened (previously this path threw, surfacing
        // as an error — still an error, never a fake success).
        if (result == null || result.length() == 0) return "{}";
        try {
            JSONObject out = new JSONObject(result.toString());
            String hash = out.optString("hash",
                    out.optString("tx_hash", out.optString("txHash", "")));
            if (!hash.isEmpty()) out.put("hash", hash);
            out.put("accepted", true);
            out.put("success", true);
            return out.toString();
        } catch (JSONException e) {
            return result.toString();
        }
    }
}
