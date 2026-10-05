package com.octopus.wallet;

import android.annotation.SuppressLint;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.util.Log;
import android.view.KeyEvent;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.EditText;
import android.widget.ImageButton;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.HashMap;
import java.util.Map;
import java.util.Set;

/**
 * In-app DApp browser with window.octra provider injection.
 * <p>
 * Loads DApp URLs in a WebView and injects the Octra wallet provider,
 * allowing DApps to interact with the native wallet for signing, balance
 * queries, and contract calls — just like the Chrome extension.
 * <p>
 * Origin validation uses {@link DappOriginStore}.
 */
public class DappBrowserActivity extends AppCompatActivity {

    private static final String DEFAULT_URL = "http://localhost:3000";

    private WebView webView;
    private EditText urlInput;
    private ProgressBar progressBar;
    private LinearLayout connectionStatus;
    private TextView connectionText;

    private boolean isConnected = false;
    private String connectedAddress = null;

    // ─── Lifecycle ─────────────────────────────────────────────────────

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_dapp_browser);

        webView = findViewById(R.id.webView);
        urlInput = findViewById(R.id.urlInput);
        progressBar = findViewById(R.id.progressBar);
        connectionStatus = findViewById(R.id.connectionStatus);
        connectionText = findViewById(R.id.connectionText);

        ImageButton btnBack = findViewById(R.id.btnBack);
        ImageButton btnGo = findViewById(R.id.btnGo);
        ImageButton btnClose = findViewById(R.id.btnClose);

        // URL bar actions
        btnBack.setOnClickListener(v -> { if (webView.canGoBack()) webView.goBack(); });
        btnGo.setOnClickListener(v -> navigateToUrl());
        btnClose.setOnClickListener(v -> finish());

        urlInput.setOnEditorActionListener((v, actionId, event) -> {
            if (actionId == EditorInfo.IME_ACTION_GO ||
                (event != null && event.getKeyCode() == KeyEvent.KEYCODE_ENTER)) {
                navigateToUrl();
                return true;
            }
            return false;
        });

        // Configure WebView
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setCacheMode(WebSettings.LOAD_DEFAULT);

        // Add JavaScript interface for native wallet bridge
        webView.addJavascriptInterface(new OctraWalletBridge(), "OctraWalletBridge");

        // WebView clients
        webView.setWebViewClient(new DappWebViewClient());
        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onProgressChanged(WebView view, int newProgress) {
                if (newProgress < 100) {
                    progressBar.setVisibility(View.VISIBLE);
                    progressBar.setProgress(newProgress);
                } else {
                    progressBar.setVisibility(View.GONE);
                }
            }
        });

        // Load from intent or default
        String intentUrl = getIntent().getStringExtra("url");
        String url = (intentUrl != null && !intentUrl.isEmpty()) ? intentUrl : DEFAULT_URL;
        urlInput.setText(url);
        webView.loadUrl(url);
    }

    @Override
    public void onBackPressed() {
        if (webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onDestroy() {
        if (webView != null) {
            webView.removeJavascriptInterface("OctraWalletBridge");
            webView.destroy();
        }
        super.onDestroy();
    }

    // ─── Navigation ────────────────────────────────────────────────────

    private void navigateToUrl() {
        String url = urlInput.getText().toString().trim();
        if (url.isEmpty()) return;
        if (isOctUrl(url)) {
            loadOctUrl(url);
            return;
        }
        if (!url.startsWith("http://") && !url.startsWith("https://")) {
            url = "https://" + url;
        }
        webView.loadUrl(url);
    }

    // ─── Origin validation ─────────────────────────────────────────────

    private boolean isOriginAllowed(String url) {
        try {
            Uri uri = Uri.parse(url);
            String host = uri.getHost();
            if (host == null) return false;
            Set<String> allowed = DappOriginStore.getAllowedOrigins(this);
            return allowed.contains(DappOriginStore.normalizeHost(host));
        } catch (Exception e) {
            return false;
        }
    }

    // ─── Provider injection ────────────────────────────────────────────

    /**
     * Injects the window.octra provider into the page, mirroring the
     * Chrome extension's inject.js API surface.
     */
    private void injectProvider() {
        String js = getOctraProviderScript();
        webView.evaluateJavascript(js, null);
    }

    /**
     * Determine the chain ID from the active network profile.
     * Returns 'octra-mainnet-1' for mainnet, 'octra-devnet-1' for devnet.
     */
    private String getActiveChainId() {
        String rpc = getNodeRpcUrl();
        if (rpc != null && rpc.contains("rpc.octrascan.io")) {
            return "octra-mainnet-1";
        }
        return "octra-devnet-1";
    }

    /**
     * Return the explorer URL for the active network.
     */
    private String getActiveExplorerUrl() {
        try {
            String raw = OctraNative.getInstance().getWalletInfo();
            if (raw != null && !raw.isEmpty()) {
                JSONObject info = new JSONObject(raw);
                String explorer = info.optString("explorer_url", "").trim();
                if (!explorer.isEmpty()) return explorer;
            }
        } catch (Exception ignored) {}
        return UrlSecurityValidator.DEFAULT_EXPLORER;
    }

    private String getOctraProviderScript() {
        String chainId = getActiveChainId();
        return "(function() {\n" +
            "  'use strict';\n" +
            "  if (window.octra) return;\n" +
            "\n" +
            "  let _requestId = 0;\n" +
            "  const _pending = new Map();\n" +
            "  const _listeners = {};\n" +
            "  let _connected = false;\n" +
            "  let _accounts = [];\n" +
            "\n" +
            "  function _emit(event, data) {\n" +
            "    for (const cb of _listeners[event] || []) { try { cb(data); } catch {} }\n" +
            "  }\n" +
            "\n" +
            "  // Bridge response handler — called from native\n" +
            "  window.__octra_response = function(id, resultJson, error) {\n" +
            "    const p = _pending.get(id);\n" +
            "    if (!p) return;\n" +
            "    _pending.delete(id);\n" +
            "    if (error) p.reject(new Error(error));\n" +
            "    else p.resolve(JSON.parse(resultJson));\n" +
            "  };\n" +
            "\n" +
            "  const octraProvider = {\n" +
            "    isOctra: true,\n" +
            "    chainId: '" + chainId + "',\n" +
            "    get accounts() { return [..._accounts]; },\n" +
            "    get isConnected() { return _connected; },\n" +
            "\n" +
            "    async connect() {\n" +
            "      const id = ++_requestId;\n" +
            "      return new Promise((resolve, reject) => {\n" +
            "        _pending.set(id, {resolve, reject});\n" +
            "        OctraWalletBridge.connect(id);\n" +
            "      }).then(r => {\n" +
            "        _connected = true; _accounts = [r.address];\n" +
            "        _emit('connect', r); _emit('accountsChanged', _accounts);\n" +
            "        return r;\n" +
            "      });\n" +
            "    },\n" +
            "\n" +
            "    async disconnect() {\n" +
            "      _connected = false; _accounts = [];\n" +
            "      _emit('disconnect'); _emit('accountsChanged', []);\n" +
            "      return {ok: true};\n" +
            "    },\n" +
            "\n" +
            "    async request({method, params = []}) {\n" +
            "      if (!_connected && method !== 'octra_accounts' && method !== 'octra_chainId')\n" +
            "        throw new Error('Not connected. Call window.octra.connect() first.');\n" +
            "      const id = ++_requestId;\n" +
            "      return new Promise((resolve, reject) => {\n" +
            "        _pending.set(id, {resolve, reject});\n" +
            "        OctraWalletBridge.request(id, method, JSON.stringify(params));\n" +
            "      });\n" +
            "    },\n" +
            "\n" +
            "    async sendTransaction(to, amount) {\n" +
            "      return this.request({method:'octra_sendTransaction', params:[{to,amount}]});\n" +
            "    },\n" +
            "    async callContract(address, method, params=[], amount='0') {\n" +
            "      return this.request({method:'octra_callContract', params:[address,method,params,amount]});\n" +
            "    },\n" +
            "    async callView(address, method, params=[]) {\n" +
            "      return this.request({method:'octra_callView', params:[address,method,params]});\n" +
            "    },\n" +
            "    async getBalance() { return this.request({method:'octra_getBalance'}); },\n" +
            "    async contractCall(opts) {\n" +
            "      return this.request({method:'octra_callContract',\n" +
            "        params:[opts.contractAddress, opts.method, opts.params||[], opts.amount||'0']});\n" +
            "    },\n" +
            "\n" +
            "    on(event, cb) { if (!_listeners[event]) _listeners[event]=[]; _listeners[event].push(cb); return this; },\n" +
            "    off(event, cb) { if (_listeners[event]) _listeners[event]=_listeners[event].filter(c=>c!==cb); return this; },\n" +
            "  };\n" +
            "\n" +
            "  Object.defineProperty(window, 'octra', {\n" +
            "    value: Object.freeze(octraProvider),\n" +
            "    writable: false, configurable: false,\n" +
            "  });\n" +
            "  window.dispatchEvent(new Event('octra#initialized'));\n" +
            "})();";
    }

    // ─── WebView Client ────────────────────────────────────────────────

    private class DappWebViewClient extends WebViewClient {
        @Override
        public void onPageFinished(WebView view, String url) {
            super.onPageFinished(view, url);
            urlInput.setText(url);
            injectProvider();
        }

        @Override
        public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
            String url = request.getUrl().toString();
            // Native oct:// protocol — render circle content directly.
            if (isOctUrl(url)) {
                loadOctUrl(url);
                return true;
            }
            // Allow http/https, block others
            if (url.startsWith("http://") || url.startsWith("https://")) {
                return false; // let WebView handle it
            }
            // Open external intents for non-web URLs
            try {
                startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
            } catch (Exception e) {
                // ignore
            }
            return true;
        }

        @Override
        public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
            String url = request.getUrl().toString();
            // Serve oct:// subresources (CSS/JS/images/fonts) straight from the node.
            if (isOctUrl(url)) {
                return fetchOctResource(url);
            }
            return super.shouldInterceptRequest(view, request);
        }

        @Override
        public boolean onRenderProcessGone(WebView view, android.webkit.RenderProcessGoneDetail detail) {
            // Never die with the renderer (e.g. OOM under memory pressure):
            // keep the activity alive and offer an explicit reload instead.
            progressBar.setVisibility(View.GONE);
            boolean crashed = detail.didCrash();
            Log.w("DappBrowser",
                    "Renderer gone (crashed=" + crashed + "), offering reload");
            new AlertDialog.Builder(DappBrowserActivity.this)
                    .setTitle(crashed ? "Page crashed" : "Page stopped")
                    .setMessage("The browser engine ran out of resources. "
                            + "Reload the page to try again.")
                    .setPositiveButton("Reload", (d, w) -> view.reload())
                    .setNegativeButton("Close", (d, w) -> finish())
                    .setCancelable(false)
                    .show();
            return true;
        }
    }

    // ─── oct:// protocol support ───────────────────────────────────────
    //
    // Octra circle URLs look like oct://<circleId>/<path> (bare circle ID
    // defaults to /index.html, mirroring the local web server gateway).
    // Content is fetched directly over JSON-RPC — no local web server
    // required — so circle pages work even with the server toggled off.
    // Interactive circle features (upload, signing) stay on the
    // localhost gateway pages, which call /api/* on the local server.

    private boolean isOctUrl(String url) {
        return OctUrlParser.isOctUrl(url);
    }

    private String[] parseOctUrl(String url) {
        return OctUrlParser.parseOctUrl(url);
    }

    private boolean isTextMime(String mime) {
        return OctUrlParser.isTextMime(mime);
    }

    private WebResourceResponse octError(int code, String reason) {
        Map<String, String> headers = new HashMap<>();
        headers.put("Cache-Control", "no-store");
        byte[] body;
        try {
            body = reason.getBytes("UTF-8");
        } catch (java.io.UnsupportedEncodingException impossible) {
            body = new byte[0];
        }
        return new WebResourceResponse("text/plain", "utf-8", code, reason,
                headers, new java.io.ByteArrayInputStream(body));
    }

    /**
     * Fetch a circle asset over RPC. Safe to call on any thread
     * (shouldInterceptRequest already runs off the UI thread).
     */
    private WebResourceResponse fetchOctResource(String url) {
        try {
            String[] parts = parseOctUrl(url);
            if (parts[0].isEmpty()) {
                return octError(400, "circle_id required");
            }
            JSONObject asset = OctraRpcClient.getInstance()
                    .circleAsset(getNodeRpcUrl(), parts[0], parts[1]);
            if (asset == null || asset.has("error")) {
                return octError(404, "Circle asset not found");
            }
            String mime = asset.optString("content_type", "application/octet-stream");
            int semi = mime.indexOf(';');
            if (semi != -1) {
                mime = mime.substring(0, semi).trim();
            }
            if (mime.isEmpty()) {
                mime = "application/octet-stream";
            }
            byte[] raw = OctraNative.getInstance()
                    .base64Decode(asset.optString("body_b64", ""));
            if (raw == null) {
                raw = new byte[0];
            }
            if (OctUrlParser.isTooLarge(raw.length)) {
                return octError(413, "Asset too large (" + raw.length
                        + " bytes, limit " + OctUrlParser.MAX_DIRECT_BYTES
                        + ") — open via the local gateway instead");
            }
            Map<String, String> headers = new HashMap<>();
            headers.put("Cache-Control", "no-store");
            headers.put("X-Content-Type-Options", "nosniff");
            String encoding = isTextMime(mime) ? "utf-8" : null;
            return new WebResourceResponse(mime, encoding, 200, "OK",
                    headers, new java.io.ByteArrayInputStream(raw));
        } catch (Exception e) {
            return octError(500, "Circle fetch failed");
        }
    }

    private byte[] readAllBytes(java.io.InputStream in) throws java.io.IOException {
        java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) != -1) {
            out.write(buf, 0, n);
        }
        return out.toByteArray();
    }

    /** Render a top-level oct:// navigation (HTML/text inline, images via data URI). */
    private void loadOctUrl(final String octUrl) {
        urlInput.setText(octUrl);
        progressBar.setVisibility(View.VISIBLE);
        ((OctraWalletApplication) getApplication()).getIoExecutor().execute(() -> {
            final WebResourceResponse res = fetchOctResource(octUrl);
            runOnUiThread(() -> {
                progressBar.setVisibility(View.GONE);
                int code = res != null ? res.getStatusCode() : 500;
                if (code == 413) {
                    // Too large to buffer: offer the streaming gateway.
                    if (LocalWebServerStore.isEnabled(this)) {
                        String[] parts = parseOctUrl(octUrl);
                        webView.loadUrl("http://127.0.0.1:" + LocalWebServerStore.PORT
                                + "/oct/" + parts[0] + parts[1]);
                    } else {
                        Toast.makeText(this, "Page too large to render directly. "
                                + "Enable Local Web Server in Settings for large circle pages.",
                                Toast.LENGTH_LONG).show();
                    }
                    return;
                }
                if (res == null || code < 200 || code >= 300) {
                    Toast.makeText(this, "Cannot open " + octUrl +
                            " (circle not found, code " + code + ")",
                            Toast.LENGTH_LONG).show();
                    return;
                }
                try {
                    byte[] raw = readAllBytes(res.getData());
                    String mime = res.getMimeType();
                    if (isTextMime(mime)) {
                        String text = new String(raw, java.nio.charset.StandardCharsets.UTF_8);
                        webView.loadDataWithBaseURL(octUrl, text, mime, "UTF-8", null);
                    } else if (mime.startsWith("image/")) {
                        String b64 = OctraNative.getInstance().base64Encode(raw);
                        webView.loadUrl("data:" + mime + ";base64," + b64);
                    } else {
                        Toast.makeText(this, "Preview not supported for " + mime,
                                Toast.LENGTH_LONG).show();
                    }
                } catch (Exception e) {
                    Toast.makeText(this, "Failed to render circle page",
                            Toast.LENGTH_LONG).show();
                }
            });
        });
    }

    // ─── JavaScript Bridge ─────────────────────────────────────────────

    /**
     * Native bridge exposed to JavaScript as OctraWalletBridge.
     * The DApp calls OctraWalletBridge.connect(id) / .request(id, method, params)
     * and receives responses via window.__octra_response(id, result, error).
     */
    private class OctraWalletBridge {

        @JavascriptInterface
        public void connect(final int requestId) {
            runOnUiThread(() -> {
                String origin = webView.getUrl();
                if (!isOriginAllowed(origin)) {
                    // Show approval dialog
                    showConnectApproval(requestId, origin);
                } else {
                    approveConnection(requestId);
                }
            });
        }

        @JavascriptInterface
        public void request(final int requestId, final String method, final String paramsJson) {
            runOnUiThread(() -> {
                if (!isConnected) {
                    sendError(requestId, "Not connected");
                    return;
                }
                handleDappRequest(requestId, method, paramsJson);
            });
        }
    }

    // ─── Connection approval ───────────────────────────────────────────

    private void showConnectApproval(int requestId, String origin) {
        String host = "Unknown";
        try { host = Uri.parse(origin).getHost(); } catch (Exception e) { /* */ }

        new AlertDialog.Builder(this)
            .setTitle("Connect to DApp")
            .setMessage("Allow " + host + " to connect to your Octra wallet?\n\n" +
                "This will share your public address with this site.")
            .setPositiveButton("Allow", (d, w) -> {
                // Add to allowed origins
                try {
                    String h = Uri.parse(origin).getHost();
                    if (h != null) DappOriginStore.addOrigin(this, h);
                } catch (Exception e) { /* */ }
                approveConnection(requestId);
            })
            .setNegativeButton("Deny", (d, w) -> {
                sendError(requestId, "User rejected connection");
            })
            .setCancelable(false)
            .show();
    }

    private void approveConnection(int requestId) {
        // Get address from WalletKeysLoader or WalletViewModel
        String address = getWalletAddress();
        String pubKey = getWalletPublicKeyB64();

        if (address == null || address.isEmpty()) {
            sendError(requestId, "Wallet not loaded");
            return;
        }

        isConnected = true;
        connectedAddress = address;

        connectionStatus.setVisibility(View.VISIBLE);
        connectionText.setText("Connected: " + address.substring(0, 10) + "...");

        try {
            JSONObject result = new JSONObject();
            result.put("address", address);
            result.put("publicKey", pubKey);
            sendResult(requestId, result.toString());
        } catch (JSONException e) {
            sendError(requestId, e.getMessage());
        }
    }

    // ─── DApp request handler ──────────────────────────────────────────

    private void handleDappRequest(int requestId, String method, String paramsJson) {
        try {
            switch (method) {
                case "octra_accounts":
                    sendResult(requestId, "[\"" + connectedAddress + "\"]");
                    break;
                case "octra_chainId":
                    sendResult(requestId, "\"" + getActiveChainId() + "\"");
                    break;
                case "octra_getBalance":
                    fetchBalance(requestId);
                    break;
                case "octra_sendTransaction":
                    handleSendTransaction(requestId, paramsJson);
                    break;
                case "octra_callContract":
                    handleCallContract(requestId, paramsJson);
                    break;
                case "octra_callView":
                    handleCallView(requestId, paramsJson);
                    break;
                default:
                    sendError(requestId, "Unsupported method: " + method);
            }
        } catch (Exception e) {
            sendError(requestId, e.getMessage());
        }
    }

    private void fetchBalance(int requestId) {
        ((OctraWalletApplication) getApplication()).getIoExecutor().execute(() -> {
            try {
                OctraRpcClient rpc = OctraRpcClient.getInstance();
                JSONObject result = rpc.call(getNodeRpcUrl(), "octra_balance", new JSONArray().put(connectedAddress));
                runOnUiThread(() -> sendResult(requestId, result.toString()));
            } catch (Exception e) {
                runOnUiThread(() -> sendError(requestId, e.getMessage()));
            }
        });
    }

    private void handleSendTransaction(int requestId, String paramsJson) {
        try {
            JSONArray params = new JSONArray(paramsJson);
            JSONObject txParams = params.getJSONObject(0);
            String to = txParams.getString("to");
            String amount = txParams.optString("amount", "0");

            // Show confirmation dialog
            new AlertDialog.Builder(this)
                .setTitle("Confirm Transaction")
                .setMessage("Send " + amount + " OCT to\n" + to + "?")
                .setPositiveButton("Confirm", (d, w) -> {
                    // Submit via the wallet's existing send flow
                    submitTransaction(requestId, to, amount, "standard", null, null);
                })
                .setNegativeButton("Cancel", (d, w) -> {
                    sendError(requestId, "User rejected transaction");
                })
                .setCancelable(false)
                .show();
        } catch (JSONException e) {
            sendError(requestId, "Invalid params: " + e.getMessage());
        }
    }

    private void handleCallContract(int requestId, String paramsJson) {
        try {
            JSONArray params = new JSONArray(paramsJson);
            String address = params.getString(0);
            String methodName = params.getString(1);
            JSONArray callParams = params.optJSONArray(2);
            String amount = params.optString(3, "0");

            new AlertDialog.Builder(this)
                .setTitle("Contract Call")
                .setMessage("Call " + methodName + " on\n" + address +
                    (!"0".equals(amount) ? "\n\nAmount: " + amount + " OCT" : ""))
                .setPositiveButton("Confirm", (d, w) -> {
                    submitTransaction(requestId, address, amount, "call",
                        methodName, callParams != null ? callParams.toString() : "[]");
                })
                .setNegativeButton("Cancel", (d, w) -> {
                    sendError(requestId, "User rejected");
                })
                .setCancelable(false)
                .show();
        } catch (JSONException e) {
            sendError(requestId, "Invalid params: " + e.getMessage());
        }
    }

    private void handleCallView(int requestId, String paramsJson) {
        ((OctraWalletApplication) getApplication()).getIoExecutor().execute(() -> {
            try {
                JSONArray params = new JSONArray(paramsJson);
                String address = params.getString(0);
                String method = params.getString(1);
                JSONArray callParams = params.optJSONArray(2);

                OctraRpcClient rpc = OctraRpcClient.getInstance();
                JSONArray rpcParams = new JSONArray();
                rpcParams.put(address);
                rpcParams.put(method);
                rpcParams.put(callParams != null ? callParams : new JSONArray());
                rpcParams.put(connectedAddress);

                JSONObject result = rpc.call(getNodeRpcUrl(), "contract_call", rpcParams);
                runOnUiThread(() -> sendResult(requestId, result.toString()));
            } catch (Exception e) {
                runOnUiThread(() -> sendError(requestId, e.getMessage()));
            }
        });
    }

    private void submitTransaction(int requestId, String to, String amount,
                                   String opType, String encryptedData, String message) {
        ((OctraWalletApplication) getApplication()).getIoExecutor().execute(() -> {
            try {
                OctraRpcClient rpc = OctraRpcClient.getInstance();
                String nodeUrl = getNodeRpcUrl();

                // Get nonce
                JSONObject balInfo = rpc.call(nodeUrl, "octra_balance", new JSONArray().put(connectedAddress));
                int nonce = balInfo.optInt("pending_nonce", balInfo.optInt("nonce", 0)) + 1;

                JSONObject tx = new JSONObject();
                tx.put("from", connectedAddress);
                tx.put("to_", to);
                tx.put("amount", amount);
                tx.put("nonce", nonce);
                tx.put("ou", "10000");
                tx.put("timestamp", System.currentTimeMillis() / 1000.0);
                tx.put("op_type", opType);
                if (encryptedData != null) tx.put("encrypted_data", encryptedData);
                if (message != null) tx.put("message", message);

                JSONObject result = rpc.call(nodeUrl, "octra_submit", new JSONArray().put(tx));
                runOnUiThread(() -> sendResult(requestId, result.toString()));
            } catch (Exception e) {
                runOnUiThread(() -> sendError(requestId, e.getMessage()));
            }
        });
    }

    // ─── JS response helpers ───────────────────────────────────────────

    private void sendResult(int requestId, String resultJson) {
        String js = "window.__octra_response(" + requestId + ", '" +
            resultJson.replace("\\", "\\\\").replace("'", "\\'") + "', null);";
        webView.evaluateJavascript(js, null);
    }

    private void sendError(int requestId, String error) {
        String js = "window.__octra_response(" + requestId + ", null, '" +
            error.replace("\\", "\\\\").replace("'", "\\'") + "');";
        webView.evaluateJavascript(js, null);
    }

    // ─── Wallet access stubs ───────────────────────────────────────────

    /**
     * Retrieve the current wallet address.
     * In production, this reads from WalletKeysLoader / WalletViewModel.
     */
    private String getWalletAddress() {
        // TODO: Integrate with WalletKeysLoader.loadAddress(context)
        // For now, check if passed via intent
        String addr = getIntent().getStringExtra("walletAddress");
        if (addr != null) return addr;
        // Fallback: read from shared prefs
        return getSharedPreferences("wallet_prefs", MODE_PRIVATE)
            .getString("active_address", null);
    }

    private String getWalletPublicKeyB64() {
        String pk = getIntent().getStringExtra("walletPublicKey");
        if (pk != null) return pk;
        return getSharedPreferences("wallet_prefs", MODE_PRIVATE)
            .getString("active_public_key", "");
    }

    /**
     * Returns the active node RPC base URL.
     * Reads from OctraNative wallet info, falls back to the compile-time default.
     */
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
