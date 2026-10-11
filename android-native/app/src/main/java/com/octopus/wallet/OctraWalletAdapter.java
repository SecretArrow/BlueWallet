package com.octopus.wallet;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * Octra network adapter: serves the legacy {@code octra_*} dialect, the
 * RFC-O-1 aliases, the 0xio third-party surface and the
 * {@code window.wallet} facade through one approval-gated pipeline.
 *
 * <p>No mock provider: reads hit the real node via {@link OctraRpcClient},
 * submits are Ed25519-signed in {@link OctraNative}, and unsupported methods
 * are refused explicitly (never simulated). All signing / account-sharing
 * paths go through {@link WalletAdapterContext#requestApproval} and a
 * dismissal counts as rejection, never approval.
 */
public final class OctraWalletAdapter implements WalletAdapter {

    private static final String ADAPTER_ID = "octra";

    private static final Set<String> SUPPORTED;

    static {
        Set<String> s = new HashSet<>();
        s.addAll(DappBridgeProtocol.LEGACY_METHODS);
        s.addAll(DappBridgeProtocol.RFC_METHODS);
        s.addAll(DappBridgeProtocol.XIO_SERVED_METHODS);
        s.addAll(DappBridgeProtocol.WALLET_SERVED_METHODS);
        SUPPORTED = Collections.unmodifiableSet(s);
    }

    @Override
    public String getAdapterId() {
        return ADAPTER_ID;
    }

    @Override
    public Set<String> getSupportedMethods() {
        return SUPPORTED;
    }

    @Override
    public boolean supports(String canonicalMethod) {
        return canonicalMethod != null && SUPPORTED.contains(canonicalMethod);
    }

    @Override
    public boolean handle(WalletAdapterContext ctx, int requestId,
                          String canonicalMethod, String paramsJson) {
        if (ctx == null || canonicalMethod == null) return false;
        try {
            switch (canonicalMethod) {
                case "octra_accounts":
                    answerAccounts(ctx, requestId);
                    return true;
                case "octra_requestAccounts":
                case "wallet_connect":
                    handleRequestAccounts(ctx, requestId, paramsJson);
                    return true;
                case "octra_chainId":
                case "wallet_getChainId":
                    ctx.sendResult(requestId, "\"" + ctx.getChainId() + "\"");
                    return true;
                case "octra_getBalance":
                case "getBalance":
                case "wallet_getBalance":
                    fetchBalance(ctx, requestId);
                    return true;
                case "octra_sendTransaction":
                case "wallet_sendTransaction":
                    handleSendTransaction(ctx, requestId, paramsJson);
                    return true;
                case "octra_sendContractTransaction":
                    handleContractTransaction(ctx, requestId, paramsJson);
                    return true;
                case "octra_callContract":
                    handleCallContract(ctx, requestId, paramsJson);
                    return true;
                case "octra_callView":
                case "wallet_callView":
                    handleCallViewLegacy(ctx, requestId, paramsJson);
                    return true;
                case "octra_getEncryptedBalance":
                    fetchEncryptedBalance(ctx, requestId);
                    return true;
                case "octra_networkInfo":
                case "wallet_getNetworkInfo":
                    ctx.sendResult(requestId, ctx.getNetworkInfo().toString());
                    return true;
                case "octra_permissions":
                case "wallet_getPermissions":
                    ctx.sendResult(requestId, new JSONArray(ctx.getPermissions()).toString());
                    return true;
                case "disconnect":
                case "wallet_disconnect":
                    ctx.clearSession();
                    ctx.sendResult(requestId, "{\"success\":true}");
                    return true;
                case "getPublicKey":
                    sendPublicKey(ctx, requestId);
                    return true;
                case "octra_switchNetwork":
                    answerSwitchNetwork(ctx, requestId, paramsJson);
                    return true;
                case "wallet_getAccounts":
                    answerAccounts(ctx, requestId);
                    return true;
                case "wallet_getAddress":
                    ctx.sendResult(requestId, "\"" + ctx.getConnectedAddress() + "\"");
                    return true;
                case "wallet_getNetwork":
                    ctx.sendResult(requestId, "\"" + networkId(ctx) + "\"");
                    return true;
                case "wallet_getNetworks":
                    ctx.sendResult(requestId, "[" + ctx.getNetworkInfo().toString() + "]");
                    return true;
                case "wallet_ping":
                    answerPing(ctx, requestId);
                    return true;
                default:
                    return false;
            }
        } catch (Exception e) {
            if (!ctx.isCancelled(requestId)) {
                ctx.sendError(requestId, safeMsg(e));
            }
            return true;
        }
    }

    // ── Reads ─────────────────────────────────────────────────────────────

    private void answerAccounts(WalletAdapterContext ctx, int requestId) {
        String addr = ctx.getConnectedAddress();
        ctx.sendResult(requestId, "[\"" + (addr == null ? "" : addr) + "\"]");
    }

    private void fetchBalance(final WalletAdapterContext ctx, final int requestId) {
        final String address = ctx.getConnectedAddress();
        if (address == null || address.isEmpty()) {
            ctx.sendError(requestId, "Wallet not loaded", DappBridgeProtocol.UNAUTHORIZED);
            return;
        }
        ctx.io().execute(() -> {
            if (!ctx.isAlive() || ctx.isCancelled(requestId)) return;
            try {
                JSONObject result = OctraRpcClient.getInstance().call(
                        ctx.getRpcUrl(), "octra_balance", new JSONArray().put(address));
                if (!ctx.isCancelled(requestId)) ctx.sendResult(requestId, result.toString());
            } catch (Exception e) {
                if (!ctx.isCancelled(requestId)) {
                    ctx.sendError(requestId, "Balance fetch failed: " + safeMsg(e),
                            DappBridgeProtocol.NETWORK_UNAVAILABLE);
                }
            }
        });
    }

    private void fetchEncryptedBalance(final WalletAdapterContext ctx, final int requestId) {
        final String address = ctx.getConnectedAddress().isEmpty()
                ? ctx.getWalletAddress() : ctx.getConnectedAddress();
        if (address == null || address.isEmpty()) {
            ctx.sendError(requestId, "Wallet not loaded", DappBridgeProtocol.UNAUTHORIZED);
            return;
        }
        ctx.io().execute(() -> {
            if (!ctx.isAlive() || ctx.isCancelled(requestId)) return;
            try {
                String sig = OctraNative.getInstance().signBalanceRequest();
                String pub = OctraNative.getInstance().getPublicKeyB64();
                JSONObject result = OctraRpcClient.getInstance().getEncryptedBalance(
                        ctx.getRpcUrl(), address, sig, pub);
                JSONObject out = new JSONObject();
                out.put("address", address);
                out.put("cipher", result == null ? "0" : result.optString("cipher", "0"));
                if (!ctx.isCancelled(requestId)) ctx.sendResult(requestId, out.toString());
            } catch (Exception e) {
                if (!ctx.isCancelled(requestId)) {
                    ctx.sendError(requestId, "Encrypted balance fetch failed: " + safeMsg(e),
                            DappBridgeProtocol.NETWORK_UNAVAILABLE);
                }
            }
        });
    }

    private void sendPublicKey(WalletAdapterContext ctx, int requestId) {
        String address = ctx.getConnectedAddress().isEmpty()
                ? ctx.getWalletAddress() : ctx.getConnectedAddress();
        if (address == null || address.isEmpty()) {
            ctx.sendError(requestId, "Wallet not loaded", DappBridgeProtocol.UNAUTHORIZED);
            return;
        }
        String pk = ctx.getWalletPublicKeyB64();
        if (pk == null || pk.isEmpty()) {
            ctx.sendError(requestId, "No public key available for the active wallet");
            return;
        }
        try {
            JSONObject o = new JSONObject();
            o.put("publicKey", pk);
            ctx.sendResult(requestId, o.toString());
        } catch (JSONException e) {
            ctx.sendError(requestId, safeMsg(e));
        }
    }

    private void answerPing(WalletAdapterContext ctx, int requestId) {
        try {
            String address = ctx.getConnectedAddress().isEmpty()
                    ? ctx.getWalletAddress() : ctx.getConnectedAddress();
            ctx.sendResult(requestId, DappBridgeProtocol.buildPing(
                    ctx.isConnected(), address == null || address.isEmpty(),
                    ctx.getOrigin(), System.currentTimeMillis()).toString());
        } catch (JSONException e) {
            ctx.sendError(requestId, safeMsg(e));
        }
    }

    private void answerSwitchNetwork(WalletAdapterContext ctx, int requestId, String paramsJson) {
        String wanted = "";
        try {
            JSONObject o = DappBridgeProtocol.asTxObject(paramsJson);
            wanted = o.optString("networkId", o.optString("network", "")).trim();
        } catch (JSONException e) {
            wanted = "";
        }
        String current = networkId(ctx);
        boolean same = !wanted.isEmpty()
                && (wanted.equalsIgnoreCase(current)
                    || wanted.equalsIgnoreCase(ctx.getChainId()));
        if (!wanted.isEmpty() && !same) {
            // Sensitive: page wants to move the wallet — ask explicitly.
            final String target = wanted;
            ctx.requestApproval("Switch network?",
                    shortOrigin(ctx) + " asks to switch to \"" + target
                            + "\". This wallet follows its configured node and stays on \""
                            + current + "\". Approve to acknowledge, cancel to refuse.",
                    approved -> {
                        if (ctx.isCancelled(requestId)) return;
                        if (!approved) {
                            ctx.sendError(requestId, "User rejected network switch",
                                    DappBridgeProtocol.USER_REJECTED);
                            return;
                        }
                        try {
                            JSONObject o = new JSONObject();
                            o.put("network", current);
                            o.put("switched", false);
                            ctx.sendResult(requestId, o.toString());
                        } catch (JSONException e) {
                            ctx.sendError(requestId, safeMsg(e));
                        }
                    });
            return;
        }
        try {
            JSONObject o = new JSONObject();
            o.put("network", current);
            o.put("switched", same);
            ctx.sendResult(requestId, o.toString());
        } catch (JSONException e) {
            ctx.sendError(requestId, safeMsg(e));
        }
    }

    // ── Approval-gated ────────────────────────────────────────────────────

    private void handleRequestAccounts(WalletAdapterContext ctx, int requestId, String paramsJson) {
        final List<String> requested =
                new ArrayList<>(DappBridgeProtocol.extractRequestedPermissions(paramsJson));
        if (ctx.isConnected()) {
            String address = ctx.getConnectedAddress();
            if (address == null || address.isEmpty()) address = ctx.getWalletAddress();
            if (address == null || address.isEmpty()) {
                ctx.sendError(requestId, "Wallet not loaded", DappBridgeProtocol.UNAUTHORIZED);
                return;
            }
            ctx.setSessionConnected(address, requested);
            ctx.sendResult(requestId, "[\"" + address + "\"]");
            return;
        }
        ctx.requestApproval("Share account with DApp",
                "Allow " + shortOrigin(ctx) + " to see your Octra address?\n\n"
                        + "This shares your public address with this site.",
                approved -> {
                    if (ctx.isCancelled(requestId)) return;
                    if (!approved) {
                        ctx.sendError(requestId, "User rejected connection",
                                DappBridgeProtocol.USER_REJECTED);
                        return;
                    }
                    String address = ctx.getWalletAddress();
                    if (address == null || address.isEmpty()) {
                        ctx.sendError(requestId, "Wallet not loaded",
                                DappBridgeProtocol.UNAUTHORIZED);
                        return;
                    }
                    ctx.setSessionConnected(address, requested);
                    ctx.sendResult(requestId, "[\"" + address + "\"]");
                });
    }

    private void handleSendTransaction(WalletAdapterContext ctx, int requestId, String paramsJson) {
        final JSONObject tx;
        try {
            tx = DappBridgeProtocol.asTxObject(paramsJson);
        } catch (JSONException e) {
            ctx.sendError(requestId, "Invalid params: " + safeMsg(e));
            return;
        }
        if (tx.optBoolean("isPrivate", false)) {
            ctx.sendError(requestId,
                    "Private transfers are not served over the provider — use the wallet UI",
                    DappBridgeProtocol.UNSUPPORTED_METHOD);
            return;
        }
        final String to = tx.optString("to", "").trim();
        if (to.isEmpty()) {
            ctx.sendError(requestId, "Invalid params: missing recipient address");
            return;
        }
        final String amount;
        try {
            amount = DappBridgeProtocol.resolveTxAmount(tx);
        } catch (JSONException e) {
            ctx.sendError(requestId, "Invalid params: " + safeMsg(e));
            return;
        }
        if ("0".equals(amount)) {
            ctx.sendError(requestId, "Invalid params: amount must be greater than 0");
            return;
        }
        String message = tx.optString("message", null);
        if (message != null) {
            message = message.trim();
            if (message.isEmpty()) message = null;
            else if (message.length() > 1000) {
                ctx.sendError(requestId, "Invalid params: message over 1000 chars");
                return;
            }
        }
        final String memo = message;
        String prompt = "Send " + amount + " micro-OCT from " + shortAddr(ctx)
                + " to\n" + to + "?\n\nOrigin: " + shortOrigin(ctx);
        if (memo != null) prompt += "\n\nMessage: " + memo;
        ctx.requestApproval("Confirm Transaction", prompt, approved -> {
            if (ctx.isCancelled(requestId)) return;
            if (!approved) {
                ctx.sendError(requestId, "User rejected transaction",
                        DappBridgeProtocol.USER_REJECTED);
                return;
            }
            submitStandard(ctx, requestId, to, amount, memo);
        });
    }

    private void handleCallContract(WalletAdapterContext ctx, int requestId, String paramsJson) {
        String t = paramsJson == null ? "" : paramsJson.trim();
        if (t.startsWith("{")) {
            JSONObject o;
            try {
                o = new JSONObject(t);
            } catch (JSONException e) {
                ctx.sendError(requestId, "Invalid params: " + safeMsg(e));
                return;
            }
            if (DappBridgeProtocol.isViewCall(o)) {
                handleCallViewObject(ctx, requestId, o);
                return;
            }
            handleContractTransaction(ctx, requestId, paramsJson);
            return;
        }
        try {
            JSONArray params = new JSONArray(paramsJson);
            String address = params.getString(0);
            String methodName = params.getString(1);
            JSONArray callParams = params.optJSONArray(2);
            String amount = params.optString(3, "0");
            final String paramsStr = callParams != null ? callParams.toString() : "[]";
            ctx.requestApproval("Contract Call",
                    "Call " + methodName + " on\n" + address
                            + (!"0".equals(amount) ? "\n\nAmount: " + amount + " micro-OCT" : "")
                            + "\n\nOrigin: " + shortOrigin(ctx),
                    approved -> {
                        if (ctx.isCancelled(requestId)) return;
                        if (!approved) {
                            ctx.sendError(requestId, "User rejected",
                                    DappBridgeProtocol.USER_REJECTED);
                            return;
                        }
                        submitContract(ctx, requestId, address, methodName, paramsStr, amount);
                    });
        } catch (JSONException e) {
            ctx.sendError(requestId, "Invalid params: " + safeMsg(e));
        }
    }

    private void handleContractTransaction(WalletAdapterContext ctx, int requestId, String paramsJson) {
        final JSONObject o;
        try {
            o = DappBridgeProtocol.asTxObject(paramsJson);
        } catch (JSONException e) {
            ctx.sendError(requestId, "Invalid params: " + safeMsg(e));
            return;
        }
        final String address = o.optString("contract", "").trim();
        final String methodName = o.optString("method", "").trim();
        if (address.isEmpty() || methodName.isEmpty()) {
            ctx.sendError(requestId, "Invalid params: call needs contract + method");
            return;
        }
        JSONArray callParams = o.optJSONArray("params");
        final String paramsStr = callParams != null ? callParams.toString() : "[]";
        final String amount;
        try {
            amount = (o.has("amount") && !o.isNull("amount"))
                    ? DappBridgeProtocol.resolveTxAmount(o) : "0";
        } catch (JSONException e) {
            ctx.sendError(requestId, "Invalid params: " + safeMsg(e));
            return;
        }
        ctx.requestApproval("Contract Call",
                "Call " + methodName + " on\n" + address
                        + (!"0".equals(amount) ? "\n\nAmount: " + amount + " micro-OCT" : "")
                        + "\n\nOrigin: " + shortOrigin(ctx),
                approved -> {
                    if (ctx.isCancelled(requestId)) return;
                    if (!approved) {
                        ctx.sendError(requestId, "User rejected",
                                DappBridgeProtocol.USER_REJECTED);
                        return;
                    }
                    submitContract(ctx, requestId, address, methodName, paramsStr, amount);
                });
    }

    private void handleCallViewObject(WalletAdapterContext ctx, int requestId, JSONObject o) {
        String address = o.optString("contract", "").trim();
        String method = o.optString("method", "").trim();
        if (address.isEmpty() || method.isEmpty()) {
            ctx.sendError(requestId, "Invalid params: view needs contract + method");
            return;
        }
        JSONArray callParams = o.optJSONArray("params");
        String caller = o.optString("caller", ctx.getConnectedAddress());
        final JSONArray finalParams = callParams != null ? callParams : new JSONArray();
        final String finalCaller = caller == null ? "" : caller;
        final String fAddress = address;
        final String fMethod = method;
        ctx.io().execute(() -> {
            if (!ctx.isAlive() || ctx.isCancelled(requestId)) return;
            try {
                JSONArray rpcParams = new JSONArray();
                rpcParams.put(fAddress);
                rpcParams.put(fMethod);
                rpcParams.put(finalParams);
                rpcParams.put(finalCaller);
                JSONObject result = OctraRpcClient.getInstance().call(
                        ctx.getRpcUrl(), "contract_call", rpcParams);
                if (!ctx.isCancelled(requestId)) ctx.sendResult(requestId, result.toString());
            } catch (Exception e) {
                if (!ctx.isCancelled(requestId)) {
                    ctx.sendError(requestId, "View call failed: " + safeMsg(e),
                            DappBridgeProtocol.NETWORK_UNAVAILABLE);
                }
            }
        });
    }

    private void handleCallViewLegacy(WalletAdapterContext ctx, int requestId, String paramsJson) {
        JSONArray params;
        try {
            params = new JSONArray(paramsJson);
        } catch (JSONException e) {
            ctx.sendError(requestId, "Invalid params: " + safeMsg(e));
            return;
        }
        final String address;
        final String method;
        try {
            address = params.getString(0);
            method = params.getString(1);
        } catch (JSONException e) {
            ctx.sendError(requestId, "Invalid params: " + safeMsg(e));
            return;
        }
        final JSONArray callParams = params.optJSONArray(2);
        ctx.io().execute(() -> {
            if (!ctx.isAlive() || ctx.isCancelled(requestId)) return;
            try {
                JSONArray rpcParams = new JSONArray();
                rpcParams.put(address);
                rpcParams.put(method);
                rpcParams.put(callParams != null ? callParams : new JSONArray());
                rpcParams.put(ctx.getConnectedAddress());
                JSONObject result = OctraRpcClient.getInstance().call(
                        ctx.getRpcUrl(), "contract_call", rpcParams);
                if (!ctx.isCancelled(requestId)) ctx.sendResult(requestId, result.toString());
            } catch (Exception e) {
                if (!ctx.isCancelled(requestId)) {
                    ctx.sendError(requestId, "View call failed: " + safeMsg(e),
                            DappBridgeProtocol.NETWORK_UNAVAILABLE);
                }
            }
        });
    }

    // ── Submission (real signing, no mocks) ─────────────────────────────────

    private void submitStandard(WalletAdapterContext ctx, int requestId,
                                String to, String amount, String memo) {
        ctx.io().execute(() -> {
            if (!ctx.isAlive() || ctx.isCancelled(requestId)) return;
            try {
                String from = ctx.getConnectedAddress();
                if (from == null || from.isEmpty()) from = ctx.getWalletAddress();
                if (from == null || from.isEmpty()) {
                    ctx.sendError(requestId, "Wallet not loaded", DappBridgeProtocol.UNAUTHORIZED);
                    return;
                }
                JSONObject bal = OctraRpcClient.getInstance().call(
                        ctx.getRpcUrl(), "octra_balance", new JSONArray().put(from));
                int nonce = bal.optInt("pending_nonce", bal.optInt("nonce", 0)) + 1;
                String signed = OctraNative.getInstance().signTransaction(to, amount, nonce, memo);
                JSONObject tx = new JSONObject(signed);
                if (tx.has("error")) {
                    throw new IllegalStateException(tx.optString("error", "Signing failed"));
                }
                JSONObject result = OctraRpcClient.getInstance().call(
                        ctx.getRpcUrl(), "octra_submit", new JSONArray().put(tx));
                if (ctx.isCancelled(requestId)) return;
                ctx.sendResult(requestId, DappBridgeProtocol.acceptedSubmitJson(result));
            } catch (Exception e) {
                if (!ctx.isCancelled(requestId)) {
                    ctx.sendError(requestId, "Submit failed: " + safeMsg(e),
                            DappBridgeProtocol.NETWORK_UNAVAILABLE);
                }
            }
        });
    }

    private void submitContract(WalletAdapterContext ctx, int requestId,
                                String contract, String method,
                                String paramsStr, String amount) {
        ctx.io().execute(() -> {
            if (!ctx.isAlive() || ctx.isCancelled(requestId)) return;
            try {
                String from = ctx.getConnectedAddress();
                if (from == null || from.isEmpty()) from = ctx.getWalletAddress();
                if (from == null || from.isEmpty()) {
                    ctx.sendError(requestId, "Wallet not loaded", DappBridgeProtocol.UNAUTHORIZED);
                    return;
                }
                JSONObject bal = OctraRpcClient.getInstance().call(
                        ctx.getRpcUrl(), "octra_balance", new JSONArray().put(from));
                int nonce = bal.optInt("pending_nonce", bal.optInt("nonce", 0)) + 1;
                String ou = recommendedOu(ctx, "call", "10000");
                String signed;
                if ("transfer".equals(method)) {
                    JSONArray params = new JSONArray(paramsStr);
                    if (params.length() < 2) {
                        throw new IllegalStateException(
                                "Transfer contract call requires [to, amount] params");
                    }
                    signed = OctraNative.getInstance().signContractCallTx(
                            contract, params.optString(0, contract),
                            String.valueOf(params.opt(1)), nonce, ou);
                } else {
                    signed = OctraNative.getInstance().signGenericContractCallTx(
                            contract, method, paramsStr, amount, nonce, ou);
                }
                JSONObject tx = new JSONObject(signed);
                if (tx.has("error")) {
                    throw new IllegalStateException(tx.optString("error", "Signing failed"));
                }
                JSONObject result = OctraRpcClient.getInstance().call(
                        ctx.getRpcUrl(), "octra_submit", new JSONArray().put(tx));
                if (ctx.isCancelled(requestId)) return;
                ctx.sendResult(requestId, DappBridgeProtocol.acceptedSubmitJson(result));
            } catch (Exception e) {
                if (!ctx.isCancelled(requestId)) {
                    ctx.sendError(requestId, "Submit failed: " + safeMsg(e),
                            DappBridgeProtocol.NETWORK_UNAVAILABLE);
                }
            }
        });
    }

    private String recommendedOu(WalletAdapterContext ctx, String op, String fallback) {
        try {
            JSONObject bucket = OctraRpcClient.getInstance().fetchFeeForOp(ctx.getRpcUrl(), op);
            if (bucket != null) {
                String rec = bucket.optString("recommended", "");
                if (!rec.isEmpty() && rec.matches("\\d+") && !"0".equals(rec)) return rec;
            }
        } catch (Exception ignored) {
            // Fall through to the safe default below.
        }
        return fallback;
    }

    // ── Small helpers ───────────────────────────────────────────────────────

    private String networkId(WalletAdapterContext ctx) {
        return DappBridgeProtocol.networkIdForChain(ctx.getChainId());
    }

    private String shortOrigin(WalletAdapterContext ctx) {
        try {
            String origin = ctx.getOrigin();
            if (origin == null || origin.isEmpty()) return "this site";
            android.net.Uri parsed = android.net.Uri.parse(origin);
            String host = parsed.getHost();
            return host == null || host.isEmpty() ? origin : host;
        } catch (Exception e) {
            return "this site";
        }
    }

    private String shortAddr(WalletAdapterContext ctx) {
        String a = ctx.getConnectedAddress();
        if (a == null || a.isEmpty()) a = ctx.getWalletAddress();
        if (a == null || a.isEmpty()) return "—";
        return a.length() > 12 ? a.substring(0, 12) + "…" : a;
    }

    private static String safeMsg(Exception e) {
        if (e == null) return "Unknown error";
        String m = e.getMessage();
        return m == null || m.isEmpty() ? e.getClass().getSimpleName() : m;
    }
}
