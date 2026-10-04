package com.octopus.wallet;

import android.content.Intent;
import android.os.Bundle;
import android.view.View;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONObject;

import java.io.File;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Derives a child wallet from an existing mnemonic wallet using a different
 * derivation index (last path component). The parent mnemonic is read from
 * MnemonicStore; no mnemonic entry is required.
 */
public class DeriveChildWalletActivity extends BaseTxActivity {

    /** Pass the parent wallet ID via this extra to pre-fill parent info. */
    static final String EXTRA_PARENT_WALLET_ID = "parent_wallet_id";

    private static final String DEFAULT_BASE_PATH = "m/44'/540'/0'/0'";

    private final ExecutorService executor = Executors.newSingleThreadExecutor();

    private TextView parentNameText;
    private TextView parentPathText;
    private EditText walletNameInput;
    private EditText indexInput;
    private View previewBtn;
    private TextView fullPathText;
    private TextView previewLabel;
    private TextView previewAddressText;
    private View deriveBtn;
    private View loadingRow;
    private TextView statusText;

    private String parentWalletId;
    private String parentMnemonic;
    private String basePath; // path without the last index component
    private String currentPreviewAddress;

    private Bip39 bip39;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        setTheme(ThemeManager.resolveThemeRes(this));
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_derive_child_wallet);
        setupToolbar(R.id.derive_child_toolbar, "Derive Child Wallet");

        bip39 = new Bip39(this);

        parentNameText    = findViewById(R.id.derive_parent_name);
        parentPathText    = findViewById(R.id.derive_parent_path);
        walletNameInput   = findViewById(R.id.derive_wallet_name);
        indexInput        = findViewById(R.id.derive_index_input);
        previewBtn        = findViewById(R.id.derive_preview_btn);
        fullPathText      = findViewById(R.id.derive_full_path_text);
        previewLabel      = findViewById(R.id.derive_preview_label);
        previewAddressText = findViewById(R.id.derive_preview_address);
        deriveBtn         = findViewById(R.id.derive_create_btn);
        loadingRow        = findViewById(R.id.derive_loading_row);
        statusText        = findViewById(R.id.derive_status_text);

        parentWalletId = getIntent().getStringExtra(EXTRA_PARENT_WALLET_ID);
        if (parentWalletId == null || parentWalletId.isEmpty()) {
            parentWalletId = WalletProfileStore.getSelectedWalletId(this);
        }

        loadParentInfo();

        previewBtn.setOnClickListener(v -> doPreview());
        deriveBtn.setOnClickListener(v -> doDerive());
    }

    // ── Load parent info ──────────────────────────────────────────────────────

    private void loadParentInfo() {
        // For child wallets, walk up to the original mnemonic parent
        String mnemWalletId = parentWalletId;
        if (MnemonicStore.isChildWallet(this, parentWalletId)) {
            String pid = MnemonicStore.getParentWalletId(this, parentWalletId);
            if (pid != null) mnemWalletId = pid;
        }

        parentMnemonic = MnemonicStore.getMnemonic(this, mnemWalletId);
        if (parentMnemonic == null) {
            showError("No mnemonic found for this wallet. Only mnemonic-type wallets support child derivation.");
            finish();
            return;
        }

        // Determine base path (all but last component)
        String fullPath = MnemonicStore.getDerivationPath(this, mnemWalletId);
        basePath = buildBasePath(fullPath);

        parentNameText.setText(mnemWalletId);
        parentPathText.setText(fullPath);
    }

    /**
     * Returns the path without the last component (the index to be replaced).
     * e.g. "m/44'/540'/0'/0'/0'" → "m/44'/540'/0'/0'"
     */
    private String buildBasePath(String fullPath) {
        String p = fullPath.trim();
        int lastSlash = p.lastIndexOf('/');
        if (lastSlash <= 1) return DEFAULT_BASE_PATH; // can't strip further
        return p.substring(0, lastSlash);
    }

    // ── Preview ───────────────────────────────────────────────────────────────

    private void doPreview() {
        String indexStr = indexInput.getText().toString().trim();
        if (indexStr.isEmpty()) {
            showError("Enter a derivation index");
            return;
        }
        int index;
        try {
            index = Integer.parseInt(indexStr);
            if (index < 0) throw new NumberFormatException();
        } catch (NumberFormatException e) {
            showError("Index must be a non-negative integer");
            return;
        }

        String derivePath = basePath + "/" + index + "'";
        fullPathText.setText("Path: " + derivePath);
        fullPathText.setVisibility(View.VISIBLE);

        setLoading(true, "Deriving preview...");

        executor.execute(() -> {
            try {
                String derivedKey = bip39.derivePrivateKeyBase64(parentMnemonic, derivePath);
                String address    = testDeriveAddress(derivedKey);
                currentPreviewAddress = address;

                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    setLoading(false, "");
                    previewLabel.setVisibility(View.VISIBLE);
                    previewAddressText.setVisibility(View.VISIBLE);
                    previewAddressText.setText(address);
                });
            } catch (Exception e) {
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    setLoading(false, "");
                    showError("Preview failed: " + e.getMessage());
                });
            }
        });
    }

    // ── Derive ────────────────────────────────────────────────────────────────

    private void doDerive() {
        String indexStr = indexInput.getText().toString().trim();
        if (indexStr.isEmpty()) { showError("Enter a derivation index"); return; }

        int index;
        try {
            index = Integer.parseInt(indexStr);
            if (index < 0) throw new NumberFormatException();
        } catch (NumberFormatException e) {
            showError("Index must be a non-negative integer");
            return;
        }

        String pin = PinStore.getDefaultPin(this);
        if (!pin.matches("\\d{6}")) {
            showError("PIN not available — unlock wallet first");
            return;
        }

        String rawName = walletNameInput.getText().toString().trim();
        String derivePath  = basePath + "/" + index + "'";
        int    finalIndex  = index;
        String finalPin    = pin;
        String finalName   = rawName.isEmpty() ? resolveDefaultName(finalIndex) : rawName;

        setLoading(true, "Deriving wallet...");
        deriveBtn.setEnabled(false);

        executor.execute(() -> {
            String createdId  = null;
            String previousId = WalletProfileStore.getSelectedWalletId(this);
            try {
                String derivedKey = bip39.derivePrivateKeyBase64(parentMnemonic, derivePath);

                createdId = WalletProfileStore.addWallet(this, finalName);
                WalletProfileStore.setSelectedWalletId(this, createdId);
                File walletDir = WalletProfileStore.getWalletDir(this, createdId);

                OctraNative.getInstance().lockWallet();
                OctraNative.getInstance().init(walletDir.getAbsolutePath());
                String result = OctraNative.getInstance().importWallet(derivedKey, finalPin);
                JSONObject json = new JSONObject(result);

                if (json.has("error")) {
                    String err = json.optString("error", "Derivation failed");
                    if (createdId != null) WalletProfileStore.removeWallet(this, createdId);
                    restoreWallet(previousId, finalPin);
                    runOnUiThread(() -> {
                        if (isFinishing() || isDestroyed()) return;
                        setLoading(false, "");
                        deriveBtn.setEnabled(true);
                        showError(err);
                    });
                    return;
                }

                String address = json.optString("address", "");
                WalletAddressStore.putAddress(getApplicationContext(), createdId, address);

                // Find the root mnemonic wallet id
                String rootMnemId = parentWalletId;
                if (MnemonicStore.isChildWallet(this, parentWalletId)) {
                    String pid = MnemonicStore.getParentWalletId(this, parentWalletId);
                    if (pid != null) rootMnemId = pid;
                }
                MnemonicStore.saveParentWalletId(this, createdId, rootMnemId);
                MnemonicStore.saveDerivationPath(this, createdId, derivePath);

                String finalId = createdId;
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    setLoading(false, "");
                    Intent data = new Intent();
                    data.putExtra("wallet_added", true);
                    data.putExtra("wallet_id", finalId);
                    setResult(RESULT_OK, data);
                    Toast.makeText(this, "Child wallet derived!", Toast.LENGTH_SHORT).show();
                    finish();
                });

            } catch (Exception e) {
                if (createdId != null) {
                    try { WalletProfileStore.removeWallet(this, createdId); } catch (Exception ignored) {}
                }
                restoreWallet(previousId, finalPin);
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    setLoading(false, "");
                    deriveBtn.setEnabled(true);
                    showError("Derivation failed: " + e.getMessage());
                });
            }
        });
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private String testDeriveAddress(String base64Key) throws Exception {
        String defaultPin = PinStore.getDefaultPin(this);
        if (!defaultPin.matches("\\d{6}")) throw new Exception("PIN not available");

        String previousId = WalletProfileStore.getSelectedWalletId(this);
        File tempDir = new File(getFilesDir(), "temp_derive_" + System.currentTimeMillis());
        tempDir.mkdirs();
        try {
            OctraNative.getInstance().lockWallet();
            OctraNative.getInstance().init(tempDir.getAbsolutePath());
            String result = OctraNative.getInstance().importWallet(base64Key, defaultPin);
            JSONObject json = new JSONObject(result);
            if (json.has("error")) throw new Exception(json.optString("error"));
            return json.optString("address", "");
        } finally {
            restoreWallet(previousId, defaultPin);
            deleteRecursive(tempDir);
        }
    }

    private void restoreWallet(String walletId, String pin) {
        try {
            File dir = WalletProfileStore.getWalletDir(this, walletId);
            OctraNative.getInstance().lockWallet();
            OctraNative.getInstance().init(dir.getAbsolutePath());
            if (pin != null && pin.matches("\\d{6}")) {
                try { OctraNative.getInstance().unlockWallet(pin); } catch (Exception ignored) {}
            }
        } catch (Exception ignored) {}
    }

    private static void deleteRecursive(File f) {
        if (f.isDirectory()) {
            File[] children = f.listFiles();
            if (children != null) for (File c : children) deleteRecursive(c);
        }
        f.delete();
    }

    private void setLoading(boolean loading, String msg) {
        if (loadingRow != null) loadingRow.setVisibility(loading ? View.VISIBLE : View.GONE);
        if (statusText != null && msg != null && !msg.isEmpty()) statusText.setText(msg);
        if (previewBtn != null) previewBtn.setEnabled(!loading);
    }

    private String resolveDefaultName(int index) {
        List<String> ids = WalletProfileStore.getWalletIds(this);
        String candidate = "HD Index " + index;
        boolean found = false;
        for (String id : ids) {
            if (id.equalsIgnoreCase(candidate)) { found = true; break; }
        }
        if (!found) return candidate;
        int n = 2;
        while (true) {
            String c = "HD Index " + index + " (" + n + ")";
            found = false;
            for (String id : ids) {
                if (id.equalsIgnoreCase(c)) { found = true; break; }
            }
            if (!found) return c;
            n++;
        }
    }
}
