package com.octopus.wallet;

import android.content.Intent;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.EditText;
import android.widget.GridLayout;
import android.widget.ImageButton;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONObject;

import java.io.File;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Creates a new wallet from a BIP-39 seed phrase.
 *
 * Workflow:
 *  1. User optionally enters a wallet name and derivation path.
 *  2. Press Generate → random 12-word phrase is created; the derived address
 *     is tested against OctraNative to confirm it is valid.
 *  3. Press Create Now → wallet is persisted; mnemonic is stored in
 *     EncryptedSharedPreferences (MnemonicStore).
 */
public class CreateMnemonicActivity extends BaseTxActivity {

    static final String EXTRA_PARENT_WALLET_ID = "parent_wallet_id";

    private static final String DEFAULT_PATH = "m/44'/540'/0'/0'/0'";

    private final ExecutorService executor = Executors.newSingleThreadExecutor();

    private EditText nameInput;
    private EditText pathInput;
    private GridLayout wordGrid;
    private TextView emptyHint;
    private TextView previewLabel;
    private TextView previewAddress;
    private View generateBtn;
    private View createBtn;
    private View loadingRow;
    private TextView statusText;
    private ImageButton copyBtn;

    // In-memory state
    private String currentMnemonic = null;
    private String currentAddress  = null;
    private Bip39 bip39;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        setTheme(ThemeManager.resolveThemeRes(this));
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_create_mnemonic);
        setupToolbar(R.id.create_mnemonic_toolbar, "Create with Mnemonic");

        bip39 = new Bip39(this);

        nameInput     = findViewById(R.id.mnemonic_wallet_name);
        pathInput     = findViewById(R.id.mnemonic_derivation_path);
        wordGrid      = findViewById(R.id.mnemonic_word_grid);
        emptyHint     = findViewById(R.id.mnemonic_empty_hint);
        previewLabel  = findViewById(R.id.mnemonic_preview_label);
        previewAddress = findViewById(R.id.mnemonic_preview_address);
        generateBtn   = findViewById(R.id.mnemonic_generate_btn);
        createBtn     = findViewById(R.id.mnemonic_create_btn);
        loadingRow    = findViewById(R.id.mnemonic_loading_row);
        statusText    = findViewById(R.id.mnemonic_status_text);
        copyBtn       = findViewById(R.id.mnemonic_copy_btn);

        pathInput.setText(DEFAULT_PATH);

        findViewById(R.id.mnemonic_reset_path_btn).setOnClickListener(v ->
                pathInput.setText(DEFAULT_PATH));

        generateBtn.setOnClickListener(v -> doGenerate());
        createBtn.setOnClickListener(v -> doCreate());
        copyBtn.setOnClickListener(v -> {
            if (currentMnemonic != null && !currentMnemonic.isEmpty()) {
                android.content.ClipboardManager cb =
                        (android.content.ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
                if (cb != null) {
                    cb.setPrimaryClip(android.content.ClipData.newPlainText("Seed Phrase", currentMnemonic));
                }
                Toast.makeText(this, "Seed phrase copied", Toast.LENGTH_SHORT).show();
            }
        });
    }

    // ── Generate ─────────────────────────────────────────────────────────────

    private void doGenerate() {
        String path = pathInput.getText().toString().trim();
        if (path.isEmpty()) path = DEFAULT_PATH;

        try {
            bip39.parsePath(path);
        } catch (Exception e) {
            showError("Invalid derivation path: " + e.getMessage());
            return;
        }

        final String finalPath = path;
        setLoading(true, "Generating phrase...");
        createBtn.setEnabled(false);

        executor.execute(() -> {
            try {
                // Keep regenerating until we get a valid wallet (no error display)
                final String[] mnemonicResult = new String[1];
                final String[] derivedKeyResult = new String[1];
                final String[] addressResult = new String[1];

                // Regenerate until valid address is produced
                int maxAttempts = 100; // Prevent infinite loop
                int attempts = 0;
                while ((mnemonicResult[0] == null || addressResult[0] == null ||
                       addressResult[0].isEmpty() ||
                       addressResult[0].length() != 47 ||
                       !addressResult[0].startsWith("oct")) && attempts < maxAttempts) {
                    attempts++;
                    try {
                        // Generate and validate mnemonic
                        String candidate = bip39.generate();

                        // Validate mnemonic (word list + checksum)
                        if (!bip39.validate(candidate)) {
                            // Invalid mnemonic, regenerate
                            continue;
                        }

                        mnemonicResult[0] = candidate;
                        derivedKeyResult[0] = bip39.derivePrivateKeyBase64(mnemonicResult[0], finalPath);
                        addressResult[0] = testDeriveAddress(derivedKeyResult[0]);

                        // If address is invalid, clear and regenerate
                        if (addressResult[0] == null || addressResult[0].isEmpty() ||
                            addressResult[0].length() != 47 ||
                            !addressResult[0].startsWith("oct")) {
                            mnemonicResult[0] = null;
                            addressResult[0] = null;
                            // Continue loop - regenerate
                        }
                    } catch (Exception e) {
                        // Generation failed, clear and regenerate
                        mnemonicResult[0] = null;
                        derivedKeyResult[0] = null;
                        addressResult[0] = null;
                        // Continue loop - regenerate
                    }
                }

                // Check if we got a valid result
                if (mnemonicResult[0] == null || addressResult[0] == null) {
                    runOnUiThread(() -> {
                        if (isFinishing() || isDestroyed()) return;
                        setLoading(false, "");
                        showError("Failed to generate valid wallet after multiple attempts. Please try again.");
                        createBtn.setEnabled(true);
                    });
                    return;
                }

                // We have a valid wallet at this point
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    currentMnemonic = mnemonicResult[0];
                    currentAddress  = addressResult[0];
                    setLoading(false, "");
                    displayWords(mnemonicResult[0]);
                    previewLabel.setVisibility(View.VISIBLE);
                    previewAddress.setVisibility(View.VISIBLE);
                    previewAddress.setText(addressResult[0]);
                    emptyHint.setVisibility(View.GONE);
                    createBtn.setEnabled(true);
                });
            } catch (Exception e) {
                // This should never happen, but just in case
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    setLoading(false, "");
                    showError("Generation failed: " + e.getMessage());
                    createBtn.setEnabled(true);
                });
            }
        });
    }

    /**
     * Temporarily imports a key into a throwaway wallet directory to get the
     * Octra address, then restores the previous wallet state.
     */
    private String testDeriveAddress(String base64Key) throws Exception {
        String defaultPin = PinStore.getDefaultPin(this);
        if (!defaultPin.matches("\\d{6}")) {
            defaultPin = "000000"; // Fallback to a temporary PIN for the validation step
        }

        String previousId = null;
        try {
            previousId = WalletProfileStore.getSelectedWalletId(this);
        } catch (Exception ignored) {}

        // Use a temp directory (not inside wallet_profiles to avoid accidental persistence)
        File tempDir = new File(getFilesDir(), "temp_mnemonic_test_" + System.currentTimeMillis());
        tempDir.mkdirs();

        try {
            OctraNative.getInstance().lockWallet();
            OctraNative.getInstance().init(tempDir.getAbsolutePath());
            String result = OctraNative.getInstance().importWallet(base64Key, defaultPin);
            JSONObject json = new JSONObject(result);
            if (json.has("error")) {
                throw new Exception(json.optString("error", "Key derivation failed"));
            }
            return json.optString("address", "");
        } finally {
            // Restore previous wallet context
            OctraNative.getInstance().lockWallet();
            if (previousId != null && !previousId.isEmpty()) {
                try {
                    File prevDir = WalletProfileStore.getWalletDir(this, previousId);
                    OctraNative.getInstance().init(prevDir.getAbsolutePath());
                    String pin = PinStore.getDefaultPin(this);
                    if (pin.matches("\\d{6}")) {
                        try { OctraNative.getInstance().unlockWallet(pin); } catch (Exception ignored) {}
                    }
                } catch (Exception ignored) {}
            }
            // Clean up temp dir files
            deleteRecursive(tempDir);
        }
    }

    private static void deleteRecursive(File f) {
        if (f.isDirectory()) {
            File[] children = f.listFiles();
            if (children != null) for (File c : children) deleteRecursive(c);
        }
        f.delete();
    }

    private void showPinSetupDialog(final Runnable onPinSet) {
        android.app.AlertDialog.Builder builder = new android.app.AlertDialog.Builder(this);
        builder.setTitle("Set 6-Digit PIN");
        builder.setMessage("Please set a 6-digit PIN to secure your wallet.");

        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(60, 40, 60, 20);

        final EditText pinField = new EditText(this);
        pinField.setHint("Enter 6-Digit PIN");
        pinField.setInputType(android.text.InputType.TYPE_CLASS_NUMBER | android.text.InputType.TYPE_NUMBER_VARIATION_PASSWORD);
        pinField.setFilters(new android.text.InputFilter[] { new android.text.InputFilter.LengthFilter(6) });
        pinField.setPadding(20, 20, 20, 20);
        layout.addView(pinField);

        final EditText pinConfirmField = new EditText(this);
        pinConfirmField.setHint("Confirm 6-Digit PIN");
        pinConfirmField.setInputType(android.text.InputType.TYPE_CLASS_NUMBER | android.text.InputType.TYPE_NUMBER_VARIATION_PASSWORD);
        pinConfirmField.setFilters(new android.text.InputFilter[] { new android.text.InputFilter.LengthFilter(6) });
        pinConfirmField.setPadding(20, 20, 20, 20);
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
        );
        params.topMargin = 30;
        pinConfirmField.setLayoutParams(params);
        layout.addView(pinConfirmField);

        builder.setView(layout);

        builder.setPositiveButton("Set PIN", null); // Set to null first to override default dismiss behavior on click
        builder.setNegativeButton("Cancel", (dialog, which) -> dialog.cancel());

        final android.app.AlertDialog dialog = builder.create();
        dialog.show();

        dialog.getButton(android.app.AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
            String pin = pinField.getText().toString();
            String pinConfirm = pinConfirmField.getText().toString();

            if (pin.length() != 6) {
                Toast.makeText(CreateMnemonicActivity.this, "PIN must be exactly 6 digits", Toast.LENGTH_SHORT).show();
                return;
            }
            if (!pin.matches("\\d{6}")) {
                Toast.makeText(CreateMnemonicActivity.this, "PIN must contain only digits", Toast.LENGTH_SHORT).show();
                return;
            }
            if (!pin.equals(pinConfirm)) {
                Toast.makeText(CreateMnemonicActivity.this, "PINs do not match", Toast.LENGTH_SHORT).show();
                return;
            }

            PinStore.setDefaultPin(CreateMnemonicActivity.this, pin);
            dialog.dismiss();
            onPinSet.run();
        });
    }

    // ── Create Now ────────────────────────────────────────────────────────────

    private void doCreate() {
        if (currentMnemonic == null || currentMnemonic.isEmpty()) {
            showError("Press Generate first.");
            return;
        }

        String path = pathInput.getText().toString().trim();
        if (path.isEmpty()) path = DEFAULT_PATH;

        try {
            bip39.parsePath(path);
        } catch (Exception e) {
            showError("Invalid derivation path: " + e.getMessage());
            return;
        }

        String pin = PinStore.getDefaultPin(this);
        if (!pin.matches("\\d{6}")) {
            showPinSetupDialog(this::doCreate);
            return;
        }

        final String finalMnemonic = currentMnemonic;
        final String finalPath     = path;
        final String finalPin      = pin;
        String rawName = nameInput.getText().toString().trim();
        final String walletName    = rawName.isEmpty() ? resolveDefaultName() : rawName;

        setLoading(true, "Creating wallet...");
        createBtn.setEnabled(false);
        generateBtn.setEnabled(false);

        executor.execute(() -> {
            String createdId = null;
            String previousId = WalletProfileStore.getSelectedWalletId(this);
            try {
                String derivedKey = bip39.derivePrivateKeyBase64(finalMnemonic, finalPath);

                createdId = WalletProfileStore.addWallet(this, walletName);
                WalletProfileStore.setSelectedWalletId(this, createdId);
                File walletDir = WalletProfileStore.getWalletDir(this, createdId);

                OctraNative.getInstance().lockWallet();
                OctraNative.getInstance().init(walletDir.getAbsolutePath());
                String result = OctraNative.getInstance().importWallet(derivedKey, finalPin);
                JSONObject json = new JSONObject(result);

                if (json.has("error")) {
                    String errMsg = json.optString("error", "Wallet creation failed");
                    WalletProfileStore.removeWallet(this, createdId);
                    WalletProfileStore.setSelectedWalletId(this, previousId);
                    final File prevDir = WalletProfileStore.getWalletDir(this, previousId);
                    OctraNative.getInstance().lockWallet();
                    OctraNative.getInstance().init(prevDir.getAbsolutePath());
                    try { OctraNative.getInstance().unlockWallet(finalPin); } catch (Exception ignored) {}
                    runOnUiThread(() -> {
                        if (isFinishing() || isDestroyed()) return;
                        setLoading(false, "");
                        createBtn.setEnabled(true);
                        generateBtn.setEnabled(true);
                        showError(errMsg);
                    });
                    return;
                }

                String address = json.optString("address", "");
                WalletAddressStore.putAddress(getApplicationContext(), createdId, address);

                // Persist mnemonic metadata
                MnemonicStore.saveMnemonic(this, createdId, finalMnemonic);
                MnemonicStore.saveDerivationPath(this, createdId, finalPath);

                String finalCreatedId = createdId;
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    setLoading(false, "");
                    Intent data = new Intent();
                    data.putExtra("wallet_added", true);
                    data.putExtra("wallet_id", finalCreatedId);
                    setResult(RESULT_OK, data);
                    Toast.makeText(this, "Mnemonic wallet created!", Toast.LENGTH_SHORT).show();
                    finish();
                });

            } catch (Exception e) {
                if (createdId != null) {
                    try { WalletProfileStore.removeWallet(this, createdId); } catch (Exception ignored) {}
                }
                // Restore previous wallet
                try {
                    WalletProfileStore.setSelectedWalletId(this, previousId);
                    File prevDir = WalletProfileStore.getWalletDir(this, previousId);
                    OctraNative.getInstance().lockWallet();
                    OctraNative.getInstance().init(prevDir.getAbsolutePath());
                    try { OctraNative.getInstance().unlockWallet(finalPin); } catch (Exception ignored) {}
                } catch (Exception ignored) {}

                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    setLoading(false, "");
                    createBtn.setEnabled(true);
                    generateBtn.setEnabled(true);
                    showError("Creation failed: " + e.getMessage());
                });
            }
        });
    }

    // ── UI helpers ────────────────────────────────────────────────────────────

    private void displayWords(String mnemonic) {
        wordGrid.removeAllViews();
        String[] words = mnemonic.split("\\s+");
        
        String currentTheme = ThemeManager.getCurrentTheme(this);
        int textColor;
        int surfaceColor;
        
        switch (currentTheme) {
            case ThemeManager.THEME_MOONBLOOM:
                textColor = getColor(R.color.text_primary_moonbloom);
                surfaceColor = getColor(R.color.surface_moonbloom);
                break;
            case ThemeManager.THEME_FROSTLINE:
                textColor = getColor(R.color.text_primary_frostline);
                surfaceColor = getColor(R.color.surface_frostline);
                break;
            case ThemeManager.THEME_SIGNAL:
                textColor = getColor(R.color.text_primary_signal);
                surfaceColor = getColor(R.color.surface_signal);
                break;
            case ThemeManager.THEME_NIGHTPULSE:
                textColor = getColor(R.color.text_primary_nightpulse);
                surfaceColor = getColor(R.color.surface_nightpulse);
                break;
            case ThemeManager.THEME_OBSIDIANGRID:
                textColor = getColor(R.color.text_primary_obsidiangrid);
                surfaceColor = getColor(R.color.surface_obsidiangrid);
                break;
            case ThemeManager.THEME_NEONFORGE:
                textColor = getColor(R.color.text_primary_neonforge);
                surfaceColor = getColor(R.color.surface_neonforge);
                break;
            case ThemeManager.THEME_IVORYCIRCUIT:
                textColor = getColor(R.color.text_primary_ivorycircuit);
                surfaceColor = getColor(R.color.surface_ivorycircuit);
                break;
            case ThemeManager.THEME_SOLARPAPER:
                textColor = getColor(R.color.text_primary_solarpaper);
                surfaceColor = getColor(R.color.surface_solarpaper);
                break;
            case ThemeManager.THEME_MISTTERMINAL:
                textColor = getColor(R.color.text_primary_mistterminal);
                surfaceColor = getColor(R.color.surface_mistterminal);
                break;
            case ThemeManager.THEME_ZENITH:
            default:
                textColor = getColor(R.color.text_primary);
                surfaceColor = getColor(R.color.surface);
                break;
        }

        for (int i = 0; i < words.length; i++) {
            TextView wordView = new TextView(this);
            wordView.setText((i + 1) + ". " + words[i]);
            wordView.setTextSize(13f);
            wordView.setTextColor(textColor);
            
            GridLayout.LayoutParams lp = new GridLayout.LayoutParams();
            lp.columnSpec = GridLayout.spec(i % 3, 1f);
            lp.rowSpec    = GridLayout.spec(i / 3);
            lp.width = 0;
            lp.height = android.view.ViewGroup.LayoutParams.WRAP_CONTENT;
            lp.setMargins(6, 6, 6, 6);
            wordView.setLayoutParams(lp);
            
            wordView.setPadding(8, 12, 8, 12);
            
            android.graphics.drawable.GradientDrawable gd = new android.graphics.drawable.GradientDrawable();
            gd.setShape(android.graphics.drawable.GradientDrawable.RECTANGLE);
            gd.setColor(surfaceColor);
            gd.setCornerRadius(16f);
            
            int strokeColor = (textColor & 0x00FFFFFF) | 0x22000000;
            gd.setStroke(2, strokeColor);
            
            wordView.setBackground(gd);
            wordView.setTextAlignment(View.TEXT_ALIGNMENT_CENTER);
            wordGrid.addView(wordView);
        }
    }

    private void setLoading(boolean loading, String message) {
        if (loadingRow != null) loadingRow.setVisibility(loading ? View.VISIBLE : View.GONE);
        if (statusText != null && message != null && !message.isEmpty()) statusText.setText(message);
        if (generateBtn != null) generateBtn.setEnabled(!loading);
    }

    private String resolveDefaultName() {
        java.util.List<String> ids = WalletProfileStore.getWalletIds(this);
        int n = 1;
        while (true) {
            String candidate = "HD Wallet " + n;
            boolean found = false;
            for (String id : ids) {
                if (id.equalsIgnoreCase(candidate)) { found = true; break; }
            }
            if (!found) return candidate;
            n++;
        }
    }
}
