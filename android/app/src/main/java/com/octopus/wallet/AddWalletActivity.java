package com.octopus.wallet;

import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.view.View;
import android.widget.EditText;
import android.widget.TextView;

import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class AddWalletActivity extends BaseTxActivity {
    private final ExecutorService executor = Executors.newSingleThreadExecutor();

    private EditText walletNameInput;
    private EditText importNameInput;
    private EditText privateKeyInput;
    private View submitButton;
    private View loadingRow;
    private TextView statusText;
    private View generateButton;
    private com.google.android.material.floatingactionbutton.FloatingActionButton fabMain;
    private com.google.android.material.floatingactionbutton.FloatingActionButton fabImportKey;
    private com.google.android.material.floatingactionbutton.FloatingActionButton fabImportFile;
    private com.google.android.material.floatingactionbutton.FloatingActionButton fabNewAccount;
    private com.google.android.material.floatingactionbutton.FloatingActionButton fabMnemonic;
    private View fabImportKeyLabel;
    private View fabImportFileLabel;
    private View fabNewAccountLabel;
    private View fabMnemonicLabel;
    private View generateCard;
    private View mnemonicCard;
    private boolean fabMenuOpen = false;
    private static final int IMPORT_FILE_REQUEST_CODE = 101;
    private static final int WALLET_FILE_PIN_REQUEST_CODE = 102;
    private Uri pendingImportFileUri;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        setTheme(ThemeManager.resolveThemeRes(this));
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_add_wallet);
        setupToolbar(R.id.add_wallet_toolbar, "Add Account");

        walletNameInput = findViewById(R.id.add_wallet_name_input);
        importNameInput = findViewById(R.id.add_wallet_import_name_input);
        privateKeyInput = findViewById(R.id.add_wallet_private_key_input);
        submitButton = findViewById(R.id.add_wallet_submit_button);
        loadingRow = findViewById(R.id.add_wallet_loading_row);
        statusText = findViewById(R.id.add_wallet_status_text);

        submitButton.setOnClickListener(v -> submitImport());

        generateButton = findViewById(R.id.add_wallet_generate_button);
        generateButton.setOnClickListener(v -> {
            String pin = PinStore.getDefaultPin(this);
            if (!pin.matches("\\d{6}")) {
                showError("Default PIN not available. Please unlock your wallet first.");
                return;
            }
            setLoadingState(true, "Generating account...");
            executor.execute(() -> {
                try {
                    String accountName = resolveAccountName();
                    String createdWalletId = WalletProfileStore.addWallet(this, accountName);
                    WalletProfileStore.setSelectedWalletId(this, createdWalletId);
                    File walletDir = WalletProfileStore.getWalletDir(this, createdWalletId);
                    OctraNative.getInstance().lockWallet();
                    OctraNative.getInstance().init(walletDir.getAbsolutePath());
                    String result = OctraNative.getInstance().createWallet(pin);
                    final JSONObject json = new JSONObject(result);
                    if (json.has("error")) {
                        WalletProfileStore.removeWallet(this, createdWalletId);
                        runOnUiThread(() -> {
                            if (isFinishing() || isDestroyed()) return;
                            setLoadingState(false, "");
                            showError(json.optString("error", "Account generation failed"));
                        });
                        return;
                    }
                    runOnUiThread(() -> {
                        if (isFinishing() || isDestroyed()) return;
                        setLoadingState(false, "");
                        try {
                            String generatedAddress = json.optString("address", "");
                            WalletAddressStore.putAddress(getApplicationContext(), createdWalletId, generatedAddress);
                        } catch (Exception ignored) {
                        }
                        Intent data = new Intent();
                        data.putExtra("wallet_added", true);
                        data.putExtra("wallet_id", createdWalletId);
                        setResult(RESULT_OK, data);
                        showSuccess("Account generated successfully");
                        finish();
                    });
                } catch (Exception e) {
                    runOnUiThread(() -> {
                        if (isFinishing() || isDestroyed()) return;
                        setLoadingState(false, "");
                        showError("Account generation failed: " + e.getMessage());
                    });
                }
            });
        });

        // FAB menu
        fabMain = findViewById(R.id.fab_import_main);
        fabImportKey = findViewById(R.id.fab_import_key);
        fabImportFile = findViewById(R.id.fab_import_file);
        fabNewAccount = findViewById(R.id.fab_new_account);
        fabMnemonic = findViewById(R.id.fab_mnemonic);
        fabImportKeyLabel = findViewById(R.id.fab_import_key_label);
        fabImportFileLabel = findViewById(R.id.fab_import_file_label);
        fabNewAccountLabel = findViewById(R.id.fab_new_account_label);
        fabMnemonicLabel = findViewById(R.id.fab_mnemonic_label);
        generateCard = findViewById(R.id.generate_account_card);
        mnemonicCard = findViewById(R.id.mnemonic_card);

        // Seed-phrase wallet creation is the default flow.
        if (mnemonicCard != null) mnemonicCard.setVisibility(View.VISIBLE);
        if (generateCard != null) generateCard.setVisibility(View.GONE);
        View importCard = findViewById(R.id.import_key_card);
        if (importCard != null) importCard.setVisibility(View.GONE);

        // Mnemonic card primary button → launch CreateMnemonicActivity
        View btnCreateMnemonic = findViewById(R.id.btn_create_mnemonic);
        if (btnCreateMnemonic != null) {
            btnCreateMnemonic.setOnClickListener(v -> {
                startActivityForResult(
                    new Intent(this, CreateMnemonicActivity.class), 200);
            });
        }

        fabMain.setOnClickListener(v -> toggleFabMenu());
        fabNewAccount.setOnClickListener(v -> {
            closeFabMenu();
            // Show generate card, hide mnemonic/import cards
            if (mnemonicCard != null) mnemonicCard.setVisibility(View.GONE);
            if (generateCard != null) generateCard.setVisibility(View.VISIBLE);
            if (importCard != null) importCard.setVisibility(View.GONE);
        });
        fabMnemonic.setOnClickListener(v -> {
            closeFabMenu();
            startActivityForResult(new Intent(this, CreateMnemonicActivity.class), 200);
        });
        fabImportKey.setOnClickListener(v -> {
            closeFabMenu();
            // Show import key card, hide mnemonic/generate cards
            if (mnemonicCard != null) mnemonicCard.setVisibility(View.GONE);
            if (generateCard != null) generateCard.setVisibility(View.GONE);
            if (importCard != null) importCard.setVisibility(View.VISIBLE);
        });
        fabImportFile.setOnClickListener(v -> {
            closeFabMenu();
            Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
            intent.setType("*/*");
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            startActivityForResult(Intent.createChooser(intent, "Select Wallet File"), IMPORT_FILE_REQUEST_CODE);
        });
    }

    private void toggleFabMenu() {
        if (fabMenuOpen) {
            closeFabMenu();
        } else {
            openFabMenu();
        }
    }

    private void openFabMenu() {
        fabMenuOpen = true;
        fabMain.setImageResource(android.R.drawable.ic_menu_close_clear_cancel);
        fabNewAccount.setVisibility(View.VISIBLE);
        fabImportKey.setVisibility(View.VISIBLE);
        fabImportFile.setVisibility(View.VISIBLE);
        fabMnemonic.setVisibility(View.VISIBLE);
        if (fabNewAccountLabel != null) fabNewAccountLabel.setVisibility(View.VISIBLE);
        if (fabImportKeyLabel != null) fabImportKeyLabel.setVisibility(View.VISIBLE);
        if (fabImportFileLabel != null) fabImportFileLabel.setVisibility(View.VISIBLE);
        if (fabMnemonicLabel != null) fabMnemonicLabel.setVisibility(View.VISIBLE);
        fabNewAccount.animate().translationY(-getResources().getDimensionPixelSize(R.dimen.fab_offset_1)).setDuration(200).start();
        fabImportKey.animate().translationY(-getResources().getDimensionPixelSize(R.dimen.fab_offset_2)).setDuration(200).start();
        fabImportFile.animate().translationY(-getResources().getDimensionPixelSize(R.dimen.fab_offset_3)).setDuration(200).start();
        fabMnemonic.animate().translationY(-getResources().getDimensionPixelSize(R.dimen.fab_offset_4)).setDuration(200).start();
        if (fabNewAccountLabel != null) fabNewAccountLabel.animate().translationY(-getResources().getDimensionPixelSize(R.dimen.fab_offset_1)).setDuration(200).start();
        if (fabImportKeyLabel != null) fabImportKeyLabel.animate().translationY(-getResources().getDimensionPixelSize(R.dimen.fab_offset_2)).setDuration(200).start();
        if (fabImportFileLabel != null) fabImportFileLabel.animate().translationY(-getResources().getDimensionPixelSize(R.dimen.fab_offset_3)).setDuration(200).start();
        if (fabMnemonicLabel != null) fabMnemonicLabel.animate().translationY(-getResources().getDimensionPixelSize(R.dimen.fab_offset_4)).setDuration(200).start();
    }

    private void closeFabMenu() {
        fabMenuOpen = false;
        fabMain.setImageResource(android.R.drawable.ic_input_add);
        fabNewAccount.animate().translationY(0).setDuration(200).withEndAction(() -> fabNewAccount.setVisibility(View.GONE)).start();
        fabImportKey.animate().translationY(0).setDuration(200).withEndAction(() -> fabImportKey.setVisibility(View.GONE)).start();
        fabImportFile.animate().translationY(0).setDuration(200).withEndAction(() -> fabImportFile.setVisibility(View.GONE)).start();
        fabMnemonic.animate().translationY(0).setDuration(200).withEndAction(() -> fabMnemonic.setVisibility(View.GONE)).start();
        if (fabNewAccountLabel != null) fabNewAccountLabel.animate().translationY(0).setDuration(200).withEndAction(() -> fabNewAccountLabel.setVisibility(View.GONE)).start();
        if (fabImportKeyLabel != null) fabImportKeyLabel.animate().translationY(0).setDuration(200).withEndAction(() -> fabImportKeyLabel.setVisibility(View.GONE)).start();
        if (fabImportFileLabel != null) fabImportFileLabel.animate().translationY(0).setDuration(200).withEndAction(() -> fabImportFileLabel.setVisibility(View.GONE)).start();
        if (fabMnemonicLabel != null) fabMnemonicLabel.animate().translationY(0).setDuration(200).withEndAction(() -> fabMnemonicLabel.setVisibility(View.GONE)).start();
    }

    /** Resolves wallet name from import name field; falls back to sequential naming. */
    private String resolveImportAccountName() {
        String typed = importNameInput.getText() == null ? "" : importNameInput.getText().toString().trim();
        if (!typed.isEmpty()) return typed;
        return resolveAccountName();
    }

    /** Resolves wallet name: if user-provided name is empty, use "Account N" sequential naming. */
    private String resolveAccountName() {
        String typed = walletNameInput.getText() == null ? "" : walletNameInput.getText().toString().trim();
        if (!typed.isEmpty()) return typed;

        List<String> existing = WalletProfileStore.getWalletIds(this);
        int idx = 1;
        while (true) {
            String candidate = "Account " + idx;
            boolean found = false;
            for (String id : existing) {
                if (id.equalsIgnoreCase(candidate)) { found = true; break; }
            }
            if (!found) return candidate;
            idx++;
        }
    }

    private void submitImport() {
        String walletName = resolveImportAccountName();
        String privateKey = privateKeyInput.getText() == null ? "" : privateKeyInput.getText().toString().trim();
        String pin = PinStore.getDefaultPin(this);

        if (privateKey.isEmpty()) {
            showError("Private key is required");
            return;
        }

        if (looksLikeMnemonic(privateKey)) {
            if (!pin.matches("\\d{6}")) {
                showError("Default PIN not available. Please unlock your wallet first.");
                return;
            }
            setLoadingState(true, "Detecting HD Version...");
            executor.execute(() -> importMnemonicWithAutodetect(walletName, privateKey, pin));
            return;
        }

        if (!isValidPrivateKey(privateKey)) {
            showError("Private key format is invalid");
            return;
        }
        if (!pin.matches("\\d{6}")) {
            showError("Default PIN not available. Please unlock your wallet first.");
            return;
        }

        setLoadingState(true, "Importing account...");
        String normalizedKey = normalizePrivateKey(privateKey);
        executor.execute(() -> importWallet(walletName, normalizedKey, pin));
    }

    private boolean looksLikeMnemonic(String input) {
        if (input == null) return false;
        String[] words = input.trim().split("\\s+");
        return words.length == 12 || words.length == 24;
    }

    private void importMnemonicWithAutodetect(String walletName, String mnemonic, String pin) {
        String previousWalletId = WalletProfileStore.getSelectedWalletId(this);
        String createdWalletId = WalletProfileStore.addWallet(this, walletName);
        WalletProfileStore.setSelectedWalletId(this, createdWalletId);

        OctraNative.getInstance().lockWallet();
        File walletDir = WalletProfileStore.getWalletDir(this, createdWalletId);
        OctraNative.getInstance().init(walletDir.getAbsolutePath());

        try {
            // Get active RPC node url
            List<NodeProfileStore.NodeProfile> profiles = NodeProfileStore.getProfiles(this);
            String selectedName = NodeProfileStore.getSelectedName(this);
            NodeProfileStore.NodeProfile active = NodeProfileStore.findByName(profiles, selectedName);
            String rpcUrl = (active != null) ? active.rpcUrl : UrlSecurityValidator.DEFAULT_RPC;

            // Derive addresses for HD Version 1 and HD Version 2
            String addrV1 = OctraNative.getInstance().deriveAddressFromMnemonic(mnemonic, 1);
            String addrV2 = OctraNative.getInstance().deriveAddressFromMnemonic(mnemonic, 2);

            boolean hasBalV1 = false;
            boolean hasBalV2 = false;

            if (addrV1 != null && !addrV1.isEmpty()) {
                try {
                    JSONObject balResultV1 = OctraRpcClient.getInstance().getBalance(rpcUrl, addrV1);
                    String raw = balResultV1.optString("balance_raw", "0");
                    hasBalV1 = !raw.equals("0") && !raw.isEmpty() && !raw.startsWith("-");
                } catch (Exception ignored) {}
            }

            if (addrV2 != null && !addrV2.isEmpty()) {
                try {
                    JSONObject balResultV2 = OctraRpcClient.getInstance().getBalance(rpcUrl, addrV2);
                    String raw = balResultV2.optString("balance_raw", "0");
                    hasBalV2 = !raw.equals("0") && !raw.isEmpty() && !raw.startsWith("-");
                } catch (Exception ignored) {}
            }

            int hdVersion = 2; // Default to v2
            if (hasBalV1 && !hasBalV2) {
                hdVersion = 1;
            }

            final int selectedVersion = hdVersion;
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                setLoadingState(true, "Auto-detected HD Version: v" + selectedVersion + ". Importing...");
            });

            // Call native JNI importWalletMnemonicWithVersion
            String result = OctraNative.getInstance().importWalletMnemonicWithVersion(mnemonic, pin, selectedVersion);
            JSONObject json = new JSONObject(result);

            if (json.has("error")) {
                rollbackImport(createdWalletId, previousWalletId);
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    setLoadingState(false, "");
                    showError(json.optString("error", "Mnemonic import failed"));
                });
                return;
            }

            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                setLoadingState(false, "");
                try {
                    String importedAddress = json.optString("address", "");
                    WalletAddressStore.putAddress(getApplicationContext(), createdWalletId, importedAddress);
                } catch (Exception ignored) {}

                // Persist mnemonic metadata
                MnemonicStore.saveMnemonic(this, createdWalletId, mnemonic);
                MnemonicStore.saveDerivationPath(this, createdWalletId, "m/44'/540'/0'/0'/0'");

                Intent data = new Intent();
                data.putExtra("wallet_added", true);
                data.putExtra("wallet_id", createdWalletId);
                setResult(RESULT_OK, data);
                showSuccess("Mnemonic account imported successfully (HD Version: v" + selectedVersion + ")");
                finish();
            });
        } catch (Exception e) {
            rollbackImport(createdWalletId, previousWalletId);
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                setLoadingState(false, "");
                showError("Mnemonic import failed: " + e.getMessage());
            });
        }
    }

    private boolean isValidPrivateKey(String key) {
        if (key == null) return false;
        String s = key.trim();
        // Accept base64-encoded 32-byte Ed25519 seed (44 chars with padding, or 43 without)
        if (s.matches("[A-Za-z0-9+/]{43}=?") || s.matches("[A-Za-z0-9+/]{42}==")) {
            try {
                byte[] decoded = android.util.Base64.decode(s, android.util.Base64.DEFAULT);
                return decoded.length == 32 || decoded.length == 64;
            } catch (Exception e) {
                return false;
            }
        }
        // Accept hex-encoded 32-byte Ed25519 seed (64 hex chars)
        if (s.matches("[0-9a-fA-F]{64}")) {
            return true;
        }
        return false;
    }

    /** Convert hex private key to base64 if needed; returns base64 key */
    private String normalizePrivateKey(String key) {
        if (key == null) return key;
        String s = key.trim();
        if (s.matches("[0-9a-fA-F]{64}")) {
            byte[] bytes = new byte[32];
            for (int i = 0; i < 32; i++) {
                bytes[i] = (byte) Integer.parseInt(s.substring(i * 2, i * 2 + 2), 16);
            }
            return android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP);
        }
        return s;
    }

    private void setLoadingState(boolean loading, String message) {
        if (loadingRow != null) {
            loadingRow.setVisibility(loading ? View.VISIBLE : View.GONE);
        }
        if (statusText != null && message != null && !message.trim().isEmpty()) {
            statusText.setText(message);
        }
        if (submitButton != null) {
            submitButton.setEnabled(!loading);
            submitButton.setAlpha(loading ? 0.6f : 1f);
        }
    }

    private void importWallet(String walletName, String privateKey, String pin) {
        String previousWalletId = WalletProfileStore.getSelectedWalletId(this);
        String createdWalletId = WalletProfileStore.addWallet(this, walletName);
        WalletProfileStore.setSelectedWalletId(this, createdWalletId);

        OctraNative.getInstance().lockWallet();
        File walletDir = WalletProfileStore.getWalletDir(this, createdWalletId);
        OctraNative.getInstance().init(walletDir.getAbsolutePath());

        try {
            String result = OctraNative.getInstance().importWallet(privateKey, pin);
            JSONObject json = new JSONObject(result);
            if (json.has("error")) {
                rollbackImport(createdWalletId, previousWalletId);
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    setLoadingState(false, "");
                    showError(json.optString("error", "Account import failed"));
                });
                return;
            }

            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                setLoadingState(false, "");
                try {
                    String importedAddress = json.optString("address", "");
                    WalletAddressStore.putAddress(getApplicationContext(), createdWalletId, importedAddress);
                } catch (Exception ignored) {
                }
                Intent data = new Intent();
                data.putExtra("wallet_added", true);
                data.putExtra("wallet_id", createdWalletId);
                setResult(RESULT_OK, data);
                showSuccess("Account imported successfully");
                finish();
            });
        } catch (Exception e) {
            rollbackImport(createdWalletId, previousWalletId);
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                setLoadingState(false, "");
                showError("Account import failed: " + e.getMessage());
            });
        }
    }

    /** Import a wallet.oct file: prompt for file PIN via activity, then re-import with default PIN */
    private void importWalletFile(Uri fileUri) {
        String defaultPin = PinStore.getDefaultPin(this);
        if (!defaultPin.matches("\\d{6}")) {
            showError("Default PIN not available. Please unlock your wallet first.");
            return;
        }
        pendingImportFileUri = fileUri;
        Intent intent = new Intent(this, WalletFilePinActivity.class);
        startActivityForResult(intent, WALLET_FILE_PIN_REQUEST_CODE);
    }

    private void doImportWalletFile(Uri fileUri, String filePin, String defaultPin) {
        setLoadingState(true, "Importing wallet file...");
        executor.execute(() -> {
            String previousWalletId = WalletProfileStore.getSelectedWalletId(this);
            String accountName = resolveAccountName();
            String tempWalletId = WalletProfileStore.addWallet(this, accountName);

            try {
                File tempDir = WalletProfileStore.getWalletDir(this, tempWalletId);
                File destFile = new File(tempDir, "wallet.oct");

                // Copy imported file to temp wallet directory
                try (InputStream input = getContentResolver().openInputStream(fileUri);
                     FileOutputStream output = new FileOutputStream(destFile)) {
                    if (input == null) throw new Exception("Cannot read selected file");
                    byte[] buffer = new byte[4096];
                    int len;
                    while ((len = input.read(buffer)) > 0) {
                        output.write(buffer, 0, len);
                    }
                }

                // Try to unlock with the user-provided file PIN
                OctraNative.getInstance().lockWallet();
                OctraNative.getInstance().init(tempDir.getAbsolutePath());
                String unlockResult = OctraNative.getInstance().unlockWallet(filePin);
                JSONObject unlockJson = new JSONObject(unlockResult);
                if (unlockJson.has("error")) {
                    // Wrong PIN — rollback and show error
                    rollbackImport(tempWalletId, previousWalletId);
                    runOnUiThread(() -> {
                        if (isFinishing() || isDestroyed()) return;
                        setLoadingState(false, "");
                        showError("Wrong PIN. Could not unlock the wallet file.");
                    });
                    return;
                }

                // Successfully unlocked — extract private key
                String privateKey = OctraNative.getInstance().getPrivateKey();
                if (privateKey == null || privateKey.trim().isEmpty()) {
                    rollbackImport(tempWalletId, previousWalletId);
                    runOnUiThread(() -> {
                        if (isFinishing() || isDestroyed()) return;
                        setLoadingState(false, "");
                        showError("Failed to extract private key from wallet file.");
                    });
                    return;
                }

                // Rollback temp wallet, then re-import with default PIN
                WalletProfileStore.removeWallet(this, tempWalletId);
                deleteDir(tempDir);

                // Do a fresh import using the extracted private key with default PIN
                String finalWalletId = WalletProfileStore.addWallet(this, accountName);
                WalletProfileStore.setSelectedWalletId(this, finalWalletId);
                File finalDir = WalletProfileStore.getWalletDir(this, finalWalletId);
                OctraNative.getInstance().lockWallet();
                OctraNative.getInstance().init(finalDir.getAbsolutePath());

                String importResult = OctraNative.getInstance().importWallet(privateKey, defaultPin);
                JSONObject importJson = new JSONObject(importResult);
                if (importJson.has("error")) {
                    rollbackImport(finalWalletId, previousWalletId);
                    runOnUiThread(() -> {
                        if (isFinishing() || isDestroyed()) return;
                        setLoadingState(false, "");
                        showError(importJson.optString("error", "Account import failed"));
                    });
                    return;
                }

                final String finalId = finalWalletId;
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    setLoadingState(false, "");
                    try {
                        String importedAddress = importJson.optString("address", "");
                        WalletAddressStore.putAddress(getApplicationContext(), finalId, importedAddress);
                    } catch (Exception ignored) {
                    }
                    Intent data = new Intent();
                    data.putExtra("wallet_added", true);
                    data.putExtra("wallet_id", finalId);
                    setResult(RESULT_OK, data);
                    showSuccess("Wallet file imported successfully");
                    finish();
                });
            } catch (Exception e) {
                rollbackImport(tempWalletId, previousWalletId);
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    setLoadingState(false, "");
                    showError("File import failed: " + e.getMessage());
                });
            }
        });
    }

    private void deleteDir(File dir) {
        if (dir == null || !dir.exists()) return;
        File[] files = dir.listFiles();
        if (files != null) {
            for (File f : files) {
                if (f.isDirectory()) deleteDir(f);
                else f.delete();
            }
        }
        dir.delete();
    }

    private void rollbackImport(String createdWalletId, String previousWalletId) {
        WalletProfileStore.removeWallet(this, createdWalletId);
        if (previousWalletId == null || previousWalletId.trim().isEmpty()) {
            return;
        }
        WalletProfileStore.setSelectedWalletId(this, previousWalletId);
        OctraNative.getInstance().lockWallet();
        File previousDir = WalletProfileStore.getWalletDir(this, previousWalletId);
        OctraNative.getInstance().init(previousDir.getAbsolutePath());
        String defaultPin = PinStore.getDefaultPin(this);
        if (defaultPin.matches("\\d{6}")) {
            try {
                OctraNative.getInstance().unlockWallet(defaultPin);
            } catch (Exception ignored) {
            }
        }
    }

    @Override
    @SuppressWarnings("deprecation")
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == IMPORT_FILE_REQUEST_CODE && resultCode == RESULT_OK && data != null) {
            Uri fileUri = data.getData();
            if (fileUri == null) return;

            // Check if this is a binary wallet.oct file or a text key file
            String fileName = "";
            try {
                android.database.Cursor cursor = getContentResolver().query(fileUri, null, null, null, null);
                if (cursor != null && cursor.moveToFirst()) {
                    int nameIndex = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME);
                    if (nameIndex >= 0) fileName = cursor.getString(nameIndex);
                    cursor.close();
                }
            } catch (Exception ignored) {}

            if (fileName.endsWith(".oct") || fileName.equals("octra_wallet") || fileName.contains("wallet")) {
                // Try as wallet file first
                importWalletFile(fileUri);
            } else {
                // Try reading as text private key
                try {
                    InputStream input = getContentResolver().openInputStream(fileUri);
                    if (input == null) { showError("Cannot read file"); return; }
                    byte[] bytes = new byte[4096];
                    int len = input.read(bytes);
                    input.close();
                    if (len > 0) {
                        String content = new String(bytes, 0, len).trim();
                        if (content.length() <= 256) {
                            privateKeyInput.setText(content);
                        } else {
                            // Likely a binary wallet file
                            importWalletFile(fileUri);
                        }
                    }
                } catch (Exception e) {
                    showError("Failed to read file: " + e.getMessage());
                }
            }
        } else if (requestCode == WALLET_FILE_PIN_REQUEST_CODE && resultCode == RESULT_OK && data != null) {
            String filePin = data.getStringExtra(WalletFilePinActivity.EXTRA_FILE_PIN);
            if (filePin == null || filePin.isEmpty()) return;
            if (pendingImportFileUri == null) return;
            String defaultPin = PinStore.getDefaultPin(this);
            if (!defaultPin.matches("\\d{6}")) {
                showError("Default PIN not available. Please unlock your wallet first.");
                return;
            }
            Uri uriToImport = pendingImportFileUri;
            pendingImportFileUri = null;
            doImportWalletFile(uriToImport, filePin, defaultPin);
        } else if (requestCode == 200 && resultCode == RESULT_OK && data != null) {
            // CreateMnemonicActivity finished — propagate result upstream
            setResult(RESULT_OK, data);
            finish();
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        executor.shutdown();
    }
}
