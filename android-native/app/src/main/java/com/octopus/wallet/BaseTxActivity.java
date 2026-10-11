package com.octopus.wallet;

import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.view.WindowManager;
import android.widget.TextView;

import androidx.appcompat.app.AppCompatActivity;

import com.google.android.material.appbar.MaterialToolbar;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.concurrent.ExecutorService;

public abstract class BaseTxActivity extends AppCompatActivity {
    private static final String TAG = "BaseTxActivity";

    /** Lazily-resolved repository — call {@link #repo()} instead. */
    private WalletRepository repository;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        setTheme(ThemeManager.resolveThemeRes(this));
        super.onCreate(savedInstanceState);
        // Centralized edge-to-edge (plan.txt § System Bars): content draws
        // behind system bars; WindowInsets are applied centrally in
        // onContentChanged() via InsetsHelper (status/navigation/cutout),
        // IME via adjustResize. Layouts must NOT use fitsSystemWindows —
        // it would stack a second padding on top of the helper's.
        InsetsHelper.enableEdgeToEdge(this);
        // Prevent screenshots and app-switcher thumbnails for all wallet screens
        getWindow().setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE);
    }

    @Override
    protected void onResume() {
        super.onResume();
        SessionLockActivity.recordActivity(this);
    }

    @Override
    protected void onPause() {
        super.onPause();
        SessionLockActivity.recordActivity(this);
    }

    /**
     * After every {@code setContentView()}, apply the centralized system-bar
     * policy to the window content root: status bar (top), navigation bar /
     * gesture strip (bottom) and display cutout become padding — exactly once
     * (see {@link InsetsHelper}, idempotent via stored initial padding).
     *
     * <p>IME (keyboard) is deliberately NOT added here: every form screen
     * uses {@code adjustResize} + a {@code ScrollView} with its submit button
     * inside the scrollable area, so the window resize already keeps inputs
     * visible. Adding IME padding on top of the resize would double-shift the
     * content. Dialogs with inputs (which own a separate window without
     * {@code adjustResize}) call {@code InsetsHelper.applySystemBars(view)}
     * with IME enabled explicitly.
     */
    @Override
    public void onContentChanged() {
        super.onContentChanged();
        try {
            View content = findViewById(android.R.id.content);
            if (content != null) InsetsHelper.applySystemBars(content, false);
        } catch (Exception ignored) {
            // Never crash layout for insets.
        }
    }

    @Override
    public void onUserInteraction() {
        super.onUserInteraction();
        SessionLockActivity.recordActivity(this);
    }

    // ─── Shared ExecutorService ────────────────────────────────────────────

    /**
     * Returns the process-wide shared {@link ExecutorService}.
     * Use this for ALL background I/O in subclasses instead of {@code new Thread()}.
     * The pool is owned by {@link OctraWalletApplication} and is never shut down.
     */
    protected ExecutorService ioExecutor() {
        return ((OctraWalletApplication) getApplication()).getIoExecutor();
    }

    // ─── Window Insets — prevent content from overlapping system bars ──────

    /**
     * Applies system bar insets to {@code rootView} so content is never
     * hidden behind the status bar (top) or navigation bar / gesture strip (bottom).
     *
     * <p>Delegates to the centralized {@link InsetsHelper} policy
     * (system bars + display cutout, original padding preserved, idempotent).
     * Prefer relying on the automatic application in {@link #onContentChanged};
     * call this only for a custom root view that needs insets instead of —
     * or in addition to — the window content root.
     */
    protected void applySystemBarInsets(View rootView) {
        InsetsHelper.applySystemBars(rootView, false);
    }

    // ─── Repository ────────────────────────────────────────────────────────

    /**
     * Returns a process-scoped {@link WalletRepository}.
     * Safe to call from any thread.
     */
    protected WalletRepository repo() {
        if (repository == null) {
            repository = ((OctraWalletApplication) getApplication()).getRepository();
        }
        return repository;
    }

    /**
     * Ensure the pvac public key is registered on the blockchain.
     * Must be called from a background thread before encrypt/decrypt/stealth transactions.
     */
    protected void ensurePvacRegistered(String rpcUrl, String address) throws Exception {
        repo().ensurePvacRegistered(rpcUrl, address);
    }

    /**
     * Fetch the encrypted balance cipher string for the given address.
     * Returns "0" if none available.
     */
    protected String fetchEncryptedBalance(String rpcUrl, String address) throws Exception {
        return repo().fetchEncryptedBalance(rpcUrl, address);
    }

    /**
     * Fetch the view public key for a given address.
     */
    protected String fetchViewPubkey(String rpcUrl, String address) throws Exception {
        return repo().fetchViewPubkey(rpcUrl, address);
    }

    protected int fetchNonce(String rpcUrl, String address) throws Exception {
        return repo().fetchNonce(rpcUrl, address);
    }

    protected String submitSignedTx(String rpcUrl, JSONObject tx) throws Exception {
        return repo().submitTx(rpcUrl, tx);
    }

    protected String getCurrentRpcUrl() {
        try {
            JSONObject info = new JSONObject(OctraNative.getInstance().getWalletInfo());
            String rpc = info.optString("rpc_url", "").trim();
            if (!rpc.isEmpty()) {
                return rpc;
            }
        } catch (Exception ignored) {
        }
        return UrlSecurityValidator.DEFAULT_RPC;
    }

    protected long fetchRecommendedFee(String rpcUrl, String category, long fallback) {
        return repo().fetchRecommendedFee(rpcUrl, category, fallback);
    }

    // ─── Error / Success display ───────────────────────────────────────────

    /**
     * Show a critical error in a MaterialAlertDialog.
     * Uses {@link ErrorDisplayHelper} — much more visible than a Toast.
     */
    protected void showError(String message) {
        String component = getClass().getSimpleName();
        String fullMessage = AppErrorCode.withCode(component, message);
        ErrorDisplayHelper.showError(this, "Error", fullMessage);
    }

    /**
     * Show a brief informational Snackbar (e.g. "Address copied").
     * Falls back to the window's content root if {@link #getRootView()} returns null.
     */
    protected void showSuccess(String message) {
        View root = getRootView();
        if (root != null) {
            ErrorDisplayHelper.showInfo(root, message);
        } else {
            // Absolute fallback — still better than nothing
            android.widget.Toast.makeText(this, message, android.widget.Toast.LENGTH_SHORT).show();
        }
    }

    /**
     * Returns the root view of the current window content.
     * Subclasses may override to provide a more specific anchor view for Snackbars.
     */
    protected View getRootView() {
        return findViewById(android.R.id.content);
    }

    // ─── Toolbar ───────────────────────────────────────────────────────────

    protected void setupToolbar(int toolbarId, String title) {
        MaterialToolbar toolbar = findViewById(toolbarId);
        if (toolbar == null) {
            return;
        }
        setSupportActionBar(toolbar);
        if (getSupportActionBar() != null) {
            getSupportActionBar().setTitle(title);
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
            getSupportActionBar().setDisplayShowHomeEnabled(true);
        }
        toolbar.setNavigationOnClickListener(v -> getOnBackPressedDispatcher().onBackPressed());
    }

    protected String mapExceptionToUserMessage(Exception e, String defaultPrefix) {
        if (e == null) return defaultPrefix;
        String msg = e.getMessage();
        if (msg == null) return defaultPrefix;
        String lower = msg.toLowerCase();
        if (lower.contains("nonce") || lower.contains("invalid balance response") || lower.contains("empty balance response")) {
            return "Unable to get account nonce from node. Please check network connectivity or RPC URL.";
        }
        if (lower.contains("submit failed") || lower.contains("error")) {
            return defaultPrefix + ": " + msg;
        }
        return defaultPrefix + ": " + msg;
    }

    // ─── Balance display helpers ───────────────────────────────────────────

    /**
     * Format a raw OCT amount (in micro-OCT, i.e. ÷ 1,000,000) to a readable string.
     */
    protected String formatOctAmount(long rawAmount) {
        try {
            java.math.BigDecimal value = java.math.BigDecimal
                    .valueOf(rawAmount, 6)
                    .setScale(6, java.math.RoundingMode.DOWN)
                    .stripTrailingZeros();
            if (value.scale() < 0) value = value.setScale(0);
            return value.toPlainString();
        } catch (Exception e) {
            return String.valueOf(rawAmount);
        }
    }

    /**
     * Format a token raw amount using the given decimal places.
     */
    protected String formatTokenAmount(long rawAmount, int decimals) {
        try {
            java.math.BigDecimal value = java.math.BigDecimal
                    .valueOf(rawAmount, decimals)
                    .stripTrailingZeros();
            if (value.scale() < 0) value = value.setScale(0);
            return value.toPlainString();
        } catch (Exception e) {
            return String.valueOf(rawAmount);
        }
    }

    /**
     * Asynchronously fetch the wallet's public OCT balance and display it in
     * {@code tv} as "Available: X OCT". Uses shared ioExecutor — no thread leak.
     */
    protected void loadPublicBalance(TextView tv) {
        if (tv == null) return;
        tv.setText("Available: loading...");
        ioExecutor().execute(() -> {
            try {
                String rpcUrl = getCurrentRpcUrl();
                JSONObject info = new JSONObject(OctraNative.getInstance().getWalletInfo());
                String address = info.optString("address", "");
                if (address.isEmpty()) {
                    runOnUiThread(() -> tv.setText("Available: —"));
                    return;
                }
                WalletRepository.Result<WalletRepository.BalanceSummary> result =
                        repo().fetchBalance(rpcUrl, address);
                if (result.isSuccess()) {
                    long pub = result.getValue().publicRaw;
                    String label = "Available: " + formatOctAmount(pub) + " OCT";
                    runOnUiThread(() -> { if (!isFinishing() && !isDestroyed()) tv.setText(label); });
                } else {
                    runOnUiThread(() -> tv.setText("Available: —"));
                }
            } catch (Exception e) {
                runOnUiThread(() -> tv.setText("Available: —"));
            }
        });
    }

    /**
     * Asynchronously fetch the wallet's encrypted OCT balance and display it in
     * {@code tv} as "Available (encrypted): X OCT". Uses shared ioExecutor.
     */
    protected void loadEncryptedBalance(TextView tv) {
        if (tv == null) return;
        tv.setText("Available (encrypted): loading...");
        ioExecutor().execute(() -> {
            try {
                String rpcUrl = getCurrentRpcUrl();
                JSONObject info = new JSONObject(OctraNative.getInstance().getWalletInfo());
                String address = info.optString("address", "");
                if (address.isEmpty()) {
                    runOnUiThread(() -> tv.setText("Available (encrypted): —"));
                    return;
                }
                WalletRepository.Result<WalletRepository.BalanceSummary> result =
                        repo().fetchBalance(rpcUrl, address);
                if (result.isSuccess()) {
                    long enc = result.getValue().encryptedRaw;
                    String label = "Available (encrypted): " + formatOctAmount(enc) + " OCT";
                    runOnUiThread(() -> { if (!isFinishing() && !isDestroyed()) tv.setText(label); });
                } else {
                    runOnUiThread(() -> tv.setText("Available (encrypted): —"));
                }
            } catch (Exception e) {
                runOnUiThread(() -> tv.setText("Available (encrypted): —"));
            }
        });
    }

    /**
     * Asynchronously fetch a token balance via contract view and display it in
     * {@code tv} as "Available: X [symbol]". Uses shared ioExecutor.
     */
    protected void loadTokenBalance(TextView tv, String tokenAddress,
                                    String tokenSymbol, int tokenDecimals) {
        if (tv == null) return;
        if (tokenAddress == null || tokenAddress.trim().isEmpty()) {
            loadPublicBalance(tv);
            return;
        }
        tv.setText("Available: loading...");
        ioExecutor().execute(() -> {
            try {
                String rpcUrl = getCurrentRpcUrl();
                JSONObject info = new JSONObject(OctraNative.getInstance().getWalletInfo());
                String address = info.optString("address", "");
                if (address.isEmpty()) {
                    runOnUiThread(() -> tv.setText("Available: —"));
                    return;
                }
                JSONObject viewResult = repo().contractView(
                        rpcUrl, tokenAddress.trim(), "balance_of",
                        new JSONArray().put(address), address);
                String rawStr = viewResult != null ? viewResult.optString("result", "0") : "0";
                long rawAmount = 0;
                try { rawAmount = Long.parseLong(rawStr.trim()); } catch (Exception ignored) {}
                String sym = (tokenSymbol != null && !tokenSymbol.isEmpty()) ? tokenSymbol : "TOKEN";
                String label = "Available: " + formatTokenAmount(rawAmount, tokenDecimals) + " " + sym;
                final String finalLabel = label;
                runOnUiThread(() -> { if (!isFinishing() && !isDestroyed()) tv.setText(finalLabel); });
            } catch (Exception e) {
                runOnUiThread(() -> tv.setText("Available: —"));
            }
        });
    }
}
