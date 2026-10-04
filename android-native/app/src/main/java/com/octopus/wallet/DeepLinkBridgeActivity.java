package com.octopus.wallet;

import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.view.WindowManager;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;

import org.json.JSONArray;
import org.json.JSONObject;

/**
 * Handles Direct Deep Linking from external browsers.
 *
 * <p>Receives deep links with scheme {@code octra-wallet://} and action paths:
 * <ul>
 *   <li>{@code octra-wallet://connect?callback=...&requestId=...}</li>
 *   <li>{@code octra-wallet://sign-tx?to=...&amount=...&callback=...&requestId=...}</li>
 *   <li>{@code octra-wallet://contract-call?address=...&method=...&params=...&callback=...&requestId=...}</li>
 * </ul>
 *
 * <p>After user approval, opens the callback URL in the browser with result parameters.
 * This enables browser DApps to communicate with the wallet APK without
 * any localhost server — the Android OS handles URL scheme routing.
 */
public class DeepLinkBridgeActivity extends AppCompatActivity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE);
        handleIntent(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handleIntent(intent);
    }

    private void handleIntent(Intent intent) {
        if (intent == null || intent.getData() == null) {
            finish();
            return;
        }

        Uri data = intent.getData();
        String scheme = data.getScheme();
        if (!"octra-wallet".equals(scheme)) {
            finish();
            return;
        }

        String action = data.getHost();
        if (action == null) {
            finish();
            return;
        }

        switch (action) {
            case "connect":
                handleConnect(data);
                break;
            case "sign-tx":
                handleSignTransaction(data);
                break;
            case "contract-call":
                handleContractCall(data);
                break;
            case "sign":
                // Legacy action alias
                handleSignTransaction(data);
                break;
            case "approve":
                handleSignTransaction(data);
                break;
            default:
                sendError(data, "Unknown action: " + action);
                break;
        }
    }

    // ─── Connect ───────────────────────────────────────────────────────

    private void handleConnect(Uri data) {
        String callback = data.getQueryParameter("callback");
        String requestId = data.getQueryParameter("requestId");

        String address = getWalletAddress();
        String pubKey = getWalletPublicKeyB64();

        if (address == null || address.isEmpty()) {
            // Wallet not ready — need to unlock first
            sendError(data, "Wallet is locked. Please unlock the app first.");
            return;
        }

        String origin = callback != null ? Uri.parse(callback).getHost() : "Unknown DApp";

        new AlertDialog.Builder(this)
                .setTitle("Connect to DApp")
                .setMessage("Allow " + origin + " to connect to your wallet?\n\n"
                        + "Address: " + address.substring(0, Math.min(10, address.length())) + "…\n\n"
                        + "This will share your public address.")
                .setPositiveButton("Allow", (d, w) -> {
                    Uri.Builder uriBuilder = buildCallbackUri(callback, requestId);
                    uriBuilder.appendQueryParameter("address", address);
                    uriBuilder.appendQueryParameter("publicKey", pubKey);
                    openBrowserCallback(uriBuilder.build());
                })
                .setNegativeButton("Deny", (d, w) -> {
                    sendError(data, "User rejected connection");
                })
                .setCancelable(false)
                .show();
    }

    // ─── Sign Transaction ──────────────────────────────────────────────

    private void handleSignTransaction(Uri data) {
        String callback = data.getQueryParameter("callback");
        String requestId = data.getQueryParameter("requestId");
        String to = data.getQueryParameter("to");
        String amount = data.getQueryParameter("amount");
        String memo = data.getQueryParameter("memo");

        if (to == null || to.isEmpty()) {
            sendError(data, "Missing recipient address");
            return;
        }
        if (amount == null || amount.isEmpty()) {
            amount = "0";
        }

        String walletAddr = getWalletAddress();
        if (walletAddr == null || walletAddr.isEmpty()) {
            sendError(data, "Wallet is locked. Please unlock the app first.");
            return;
        }

        final String finalAmount = amount;
        final String finalMemo = memo;

        new AlertDialog.Builder(this)
                .setTitle("Confirm Transaction")
                .setMessage("Send " + finalAmount + " OCT\n\n"
                        + "To: " + to + "\n"
                        + (finalMemo != null && !finalMemo.isEmpty() ? "Memo: " + finalMemo + "\n" : "")
                        + "\nFrom: " + walletAddr.substring(0, Math.min(12, walletAddr.length())) + "…")
                .setPositiveButton("Confirm", (d, w) -> {
                    submitTransactionAsync(callback, requestId, to, finalAmount, "standard", null, finalMemo);
                })
                .setNegativeButton("Cancel", (d, w) -> {
                    sendError(data, "User rejected transaction");
                })
                .setCancelable(false)
                .show();
    }

    // ─── Contract Call ─────────────────────────────────────────────────

    private void handleContractCall(Uri data) {
        String callback = data.getQueryParameter("callback");
        String requestId = data.getQueryParameter("requestId");
        String contractAddr = data.getQueryParameter("address");
        String method = data.getQueryParameter("method");
        String paramsJson = data.getQueryParameter("params");
        String amount = data.getQueryParameter("amount");
        String ou = data.getQueryParameter("ou");

        if (contractAddr == null || contractAddr.isEmpty()) {
            sendError(data, "Missing contract address");
            return;
        }
        if (method == null || method.isEmpty()) {
            sendError(data, "Missing method name");
            return;
        }

        String walletAddr = getWalletAddress();
        if (walletAddr == null || walletAddr.isEmpty()) {
            sendError(data, "Wallet is locked. Please unlock the app first.");
            return;
        }

        final String finalAmount = (amount != null && !amount.isEmpty()) ? amount : "0";
        final String finalOu = (ou != null && !ou.isEmpty()) ? ou : "1000";

        // Premium Dialog configuration based on swap actions
        String title = "Contract Call";
        String message = "Call " + method + " on\n" + contractAddr
                + (!"0".equals(finalAmount) ? "\n\nAmount: " + finalAmount + " OCT" : "")
                + "\n\nFrom: " + walletAddr.substring(0, Math.min(12, walletAddr.length())) + "…";

        if ("swap_oct_to_token".equals(method)) {
            title = "Confirm Swap (OCT → tUSD)";
            double octVal = 0;
            try {
                octVal = Double.parseDouble(finalAmount);
            } catch (Exception ignored) {}
            String displayOct = String.format("%.2f", octVal / 1000000.0);
            message = "Swap " + displayOct + " OCT for tUSD.\n\n"
                    + "Contract: " + contractAddr.substring(0, Math.min(12, contractAddr.length())) + "…\n"
                    + "From: " + walletAddr.substring(0, Math.min(12, walletAddr.length())) + "…";
        } else if ("swap_token_to_oct".equals(method)) {
            title = "Confirm Swap (tUSD → OCT)";
            String displayTusd = "0.00";
            try {
                JSONArray arr = new JSONArray(paramsJson);
                if (arr.length() > 0) {
                    double rawVal = arr.optDouble(0, 0);
                    displayTusd = String.format("%.2f", rawVal / 1000000.0);
                }
            } catch (Exception ignored) {}
            message = "Swap " + displayTusd + " tUSD for OCT.\n\n"
                    + "Contract: " + contractAddr.substring(0, Math.min(12, contractAddr.length())) + "…\n"
                    + "From: " + walletAddr.substring(0, Math.min(12, walletAddr.length())) + "…";
        } else if ("grant".equals(method)) {
            title = "Approve tUSD Spend";
            String displayTusd = "0.00";
            try {
                JSONArray arr = new JSONArray(paramsJson);
                if (arr.length() > 1) {
                    double rawVal = arr.optDouble(1, 0);
                    displayTusd = String.format("%.2f", rawVal / 1000000.0);
                }
            } catch (Exception ignored) {}
            message = "Allow Swap Contract to access " + displayTusd + " tUSD for swap.\n\n"
                    + "Token: " + contractAddr.substring(0, Math.min(12, contractAddr.length())) + "…\n"
                    + "From: " + walletAddr.substring(0, Math.min(12, walletAddr.length())) + "…";
        }

        new AlertDialog.Builder(this)
                .setTitle(title)
                .setMessage(message)
                .setPositiveButton("Confirm", (d, w) -> {
                    submitTransactionAsync(callback, requestId, contractAddr, finalAmount,
                            "call", method, paramsJson != null ? paramsJson : "[]");
                })
                .setNegativeButton("Cancel", (d, w) -> {
                    sendError(data, "User rejected contract call");
                })
                .setCancelable(false)
                .show();
    }

    // ─── Transaction Submission ────────────────────────────────────────

    private void submitTransactionAsync(String callback, String requestId,
                                         String to, String amount,
                                         String opType, String encryptedData, String message) {
        ((OctraWalletApplication) getApplication()).getIoExecutor().execute(() -> {
            try {
                OctraRpcClient rpc = OctraRpcClient.getInstance();
                String nodeUrl = getNodeRpcUrl();
                String walletAddress = getWalletAddress();

                // Get nonce
                JSONObject balInfo = rpc.call(nodeUrl, "octra_balance",
                        new JSONArray().put(walletAddress));
                int nonce = balInfo.optInt("pending_nonce", balInfo.optInt("nonce", 0)) + 1;

                JSONObject tx;
                if ("call".equals(opType)) {
                    String method = encryptedData == null ? "" : encryptedData;
                    if ("transfer".equals(method)) {
                        JSONArray params = new JSONArray(message == null || message.isEmpty() ? "[]" : message);
                        if (params.length() < 2) {
                            throw new IllegalStateException("Transfer contract call requires [to, amount] params");
                        }
                        String recipient = params.optString(0, to);
                        Object tokenAmountValue = params.opt(1);
                        String tokenAmount = tokenAmountValue == null ? amount : String.valueOf(tokenAmountValue);
                        String signedTxJson = OctraNative.getInstance().signContractCallTx(
                                to,
                                recipient,
                                tokenAmount,
                                nonce,
                                "1000");
                        tx = new JSONObject(signedTxJson);
                    } else {
                        // Support generic contract call using signGenericContractCallTx
                        String signedTxJson = OctraNative.getInstance().signGenericContractCallTx(
                                to,
                                method,
                                message != null ? message : "[]",
                                amount,
                                nonce,
                                "1000");
                        tx = new JSONObject(signedTxJson);
                    }
                } else {
                    String memo = (message == null || message.isEmpty()) ? null : message;
                    String signedTxJson = OctraNative.getInstance().signTransaction(
                            to,
                            amount,
                            nonce,
                            memo);
                    tx = new JSONObject(signedTxJson);
                }

                if (tx.has("error")) {
                    throw new IllegalStateException(tx.optString("error", "Failed to sign transaction"));
                }

                // Submit
                JSONObject result = rpc.call(nodeUrl, "octra_submit", new JSONArray().put(tx));
                String txHash = result.optString("tx_hash", result.optString("hash", ""));

                runOnUiThread(() -> {
                    Uri.Builder uriBuilder = buildCallbackUri(callback, requestId);
                    uriBuilder.appendQueryParameter("tx_hash", txHash);
                    uriBuilder.appendQueryParameter("ok", "true");
                    openBrowserCallback(uriBuilder.build());
                });
            } catch (Exception e) {
                runOnUiThread(() -> {
                    Uri.Builder uriBuilder = buildCallbackUri(callback, requestId);
                    uriBuilder.appendQueryParameter("error", e.getMessage() != null ? e.getMessage() : "Transaction failed");
                    openBrowserCallback(uriBuilder.build());
                });
            }
        });
    }

    // ─── Callback helpers ──────────────────────────────────────────────

    private Uri.Builder buildCallbackUri(String callback, String requestId) {
        String base = (callback != null && !callback.isEmpty()) ? callback : "about:blank";
        Uri.Builder builder = Uri.parse(base).buildUpon();
        if (requestId != null) {
            builder.appendQueryParameter("requestId", requestId);
        }
        return builder;
    }

    private void openBrowserCallback(Uri callbackUri) {
        try {
            if (callbackUri != null && "octra-local".equals(callbackUri.getScheme())) {
                String requestId = callbackUri.getQueryParameter("requestId");
                if (requestId != null) {
                    boolean ok = "true".equals(callbackUri.getQueryParameter("ok"));
                    String txHash = callbackUri.getQueryParameter("tx_hash");
                    String error = callbackUri.getQueryParameter("error");
                    TxRequestManager.completeRequest(requestId, ok, txHash, error);
                }
                finish();
                return;
            }

            Intent browserIntent = new Intent(Intent.ACTION_VIEW, callbackUri);
            browserIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(browserIntent);
        } catch (Exception e) {
            // Fallback if no browser can handle the URL
        }
        finish();
    }

    private void sendError(Uri data, String error) {
        String callback = data.getQueryParameter("callback");
        String requestId = data.getQueryParameter("requestId");
        Uri.Builder builder = buildCallbackUri(callback, requestId);
        builder.appendQueryParameter("error", error);
        openBrowserCallback(builder.build());
    }

    // ─── Wallet access ─────────────────────────────────────────────────

    private String getWalletAddress() {
        try {
            String raw = OctraNative.getInstance().getWalletInfo();
            if (raw != null && !raw.isEmpty()) {
                JSONObject info = new JSONObject(raw);
                return info.optString("address", "");
            }
        } catch (Exception ignored) {}
        return getSharedPreferences("wallet_prefs", MODE_PRIVATE)
                .getString("active_address", null);
    }

    private String getWalletPublicKeyB64() {
        try {
            String raw = OctraNative.getInstance().getWalletInfo();
            if (raw != null && !raw.isEmpty()) {
                JSONObject info = new JSONObject(raw);
                return info.optString("public_key", "");
            }
        } catch (Exception ignored) {}
        return getSharedPreferences("wallet_prefs", MODE_PRIVATE)
                .getString("active_public_key", "");
    }

    private String getNodeRpcUrl() {
        try {
            String raw = OctraNative.getInstance().getWalletInfo();
            if (raw != null && !raw.isEmpty()) {
                JSONObject info = new JSONObject(raw);
                String rpc = info.optString("rpc_url", "").trim();
                if (!rpc.isEmpty()) return rpc;
            }
        } catch (Exception ignored) {}
        return UrlSecurityValidator.DEFAULT_RPC;
    }
}
