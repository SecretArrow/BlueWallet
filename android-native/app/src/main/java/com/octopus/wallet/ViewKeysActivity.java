package com.octopus.wallet;

import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.provider.DocumentsContract;
import android.widget.ImageButton;
import android.widget.TextView;
import android.widget.Toast;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import com.google.android.material.button.MaterialButton;
import androidx.appcompat.app.AppCompatActivity;
import com.google.android.material.appbar.MaterialToolbar;

import java.io.File;
import java.io.FileInputStream;
import java.io.OutputStream;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class ViewKeysActivity extends AppCompatActivity {
    private boolean showViewPub = false;
    private boolean showPriv = false;
    private boolean showMnemonic = false;
    private String walletId;
    private final ExecutorService executor = Executors.newSingleThreadExecutor();

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

    @Override
    public void onUserInteraction() {
        super.onUserInteraction();
        SessionLockActivity.recordActivity(this);
    }

    private TextView addressText;
    private TextView pubkeyText;
    private TextView viewPubkeyText;
    private TextView privkeyText;
    private TextView mnemonicText;
    private android.view.View mnemonicLabel;
    private android.view.View mnemonicRow;
    private ImageButton copyAddress;
    private ImageButton copyPubkey;
    private ImageButton copyViewPubkey;
    private ImageButton copyPrivkey;
    private ImageButton copyMnemonicBtn;
    private ImageButton showViewPubkey;
    private ImageButton showPrivkey;
    private ImageButton showMnemonicBtn;
    private com.google.android.material.button.MaterialButton deriveChildBtn;

    private final ActivityResultLauncher<Uri> exportFolderPicker =
            registerForActivityResult(new ActivityResultContracts.OpenDocumentTree(), this::handleExportFolderSelected);

    private final ActivityResultLauncher<Intent> pinEntryLauncher =
            registerForActivityResult(new ActivityResultContracts.StartActivityForResult(), result -> {
                if (result.getResultCode() == RESULT_OK && result.getData() != null) {
                    String pin = result.getData().getStringExtra(PinEntryActivity.EXTRA_PIN);
                    if (pin != null && pin.matches("\\d{6}")) {
                        bindKeys(pin);
                    }
                } else {
                    finish();
                }
            });

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        setTheme(ThemeManager.resolveThemeRes(this));
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_view_keys);

        MaterialToolbar toolbar = findViewById(R.id.view_keys_toolbar);
        setSupportActionBar(toolbar);
        if (getSupportActionBar() != null) {
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
            getSupportActionBar().setDisplayShowHomeEnabled(true);
            getSupportActionBar().setTitle("View Keys");
        }
        toolbar.setNavigationOnClickListener(v -> finish());

        walletId = getIntent().getStringExtra("wallet_id");
        if (walletId == null || walletId.isEmpty()) {
            walletId = WalletProfileStore.getSelectedWalletId(this);
        }

        // Export wallet button
        MaterialButton exportBtn = findViewById(R.id.export_wallet_button);
        exportBtn.setOnClickListener(v -> exportFolderPicker.launch(null));

        addressText = findViewById(R.id.key_address_text);
        pubkeyText = findViewById(R.id.key_pubkey_text);
        viewPubkeyText = findViewById(R.id.key_view_pubkey_text);
        privkeyText = findViewById(R.id.key_privkey_text);
        mnemonicText = findViewById(R.id.key_mnemonic_text);
        mnemonicLabel = findViewById(R.id.mnemonic_label);
        mnemonicRow = findViewById(R.id.mnemonic_row);

        viewPubkeyText.setText("••••••••••••••••••••••••••••••••••••••••••••••••");
        privkeyText.setText("••••••••••••••••••••••••••••••••••••••••••••••••");

        copyAddress = findViewById(R.id.copy_address_btn);
        copyPubkey = findViewById(R.id.copy_pubkey_btn);
        copyViewPubkey = findViewById(R.id.copy_view_pubkey_btn);
        copyPrivkey = findViewById(R.id.copy_privkey_btn);
        copyMnemonicBtn = findViewById(R.id.copy_mnemonic_btn);
        showViewPubkey = findViewById(R.id.show_view_pubkey_btn);
        showPrivkey = findViewById(R.id.show_privkey_btn);
        showMnemonicBtn = findViewById(R.id.show_mnemonic_btn);
        deriveChildBtn = findViewById(R.id.derive_child_wallet_button);

        // Launch PIN entry Activity
        Intent pinIntent = new Intent(this, PinEntryActivity.class);
        pinIntent.putExtra(PinEntryActivity.EXTRA_WALLET_ID, walletId);
        pinEntryLauncher.launch(pinIntent);
    }

    private void bindKeys(String pin) {
        WalletKeys keys = WalletKeysLoader.loadKeys(this, walletId, pin);

        addressText.setText(keys.address);
        pubkeyText.setText(keys.pubkey);
        viewPubkeyText.setText("••••••••••••••••••••••••••••••••••••••••••••••••");
        privkeyText.setText("••••••••••••••••••••••••••••••••••••••••••••••••");

        copyAddress.setOnClickListener(v -> copyToClipboard(keys.address, "Address copied"));
        copyPubkey.setOnClickListener(v -> copyToClipboard(keys.pubkey, "Public key copied"));

        if (keys.viewPubkey == null || keys.viewPubkey.trim().isEmpty()) {
            copyViewPubkey.setEnabled(false);
            showViewPubkey.setEnabled(false);
        } else {
            copyViewPubkey.setEnabled(true);
            showViewPubkey.setEnabled(true);
            copyViewPubkey.setOnClickListener(v -> copyToClipboard(keys.viewPubkey, "View pubkey copied"));
        }
        if (keys.privkey == null || keys.privkey.trim().isEmpty()) {
            copyPrivkey.setEnabled(false);
            showPrivkey.setEnabled(false);
        } else {
            copyPrivkey.setEnabled(true);
            showPrivkey.setEnabled(true);
            copyPrivkey.setOnClickListener(v -> copyToClipboard(keys.privkey, "Private key copied"));
        }

        showViewPubkey.setOnClickListener(v -> {
            showViewPub = !showViewPub;
            viewPubkeyText.setText(showViewPub ? keys.viewPubkey : "••••••••••••••••••••••••••••••••••••••••••••••••");
            showViewPubkey.setImageResource(showViewPub ? R.drawable.ic_visibility_off : R.drawable.ic_visibility);
        });
        showPrivkey.setOnClickListener(v -> {
            showPriv = !showPriv;
            privkeyText.setText(showPriv ? keys.privkey : "••••••••••••••••••••••••••••••••••••••••••••••••");
            showPrivkey.setImageResource(showPriv ? R.drawable.ic_visibility_off : R.drawable.ic_visibility);
        });

        // Mnemonic section — only for mnemonic wallets (root or child)
        String mnemonicWalletId = walletId;
        if (MnemonicStore.isChildWallet(this, walletId)) {
            String pid = MnemonicStore.getParentWalletId(this, walletId);
            if (pid != null) mnemonicWalletId = pid;
        }
        final String mnemonic = MnemonicStore.getMnemonic(this, mnemonicWalletId);
        if (mnemonic != null) {
            if (mnemonicLabel != null) mnemonicLabel.setVisibility(android.view.View.VISIBLE);
            if (mnemonicRow != null)   mnemonicRow.setVisibility(android.view.View.VISIBLE);
            mnemonicText.setText("••••• ••••• ••••• •••••");
            showMnemonicBtn.setOnClickListener(v -> {
                showMnemonic = !showMnemonic;
                mnemonicText.setText(showMnemonic ? mnemonic : "••••• ••••• ••••• •••••");
                showMnemonicBtn.setImageResource(showMnemonic ? R.drawable.ic_visibility_off : R.drawable.ic_visibility);
            });
            copyMnemonicBtn.setOnClickListener(v -> copyToClipboard(mnemonic, "Seed phrase copied"));

            // Derive child wallet button
            if (deriveChildBtn != null) {
                deriveChildBtn.setVisibility(android.view.View.VISIBLE);
                deriveChildBtn.setOnClickListener(v -> {
                    Intent intent = new Intent(this, DeriveChildWalletActivity.class);
                    intent.putExtra(DeriveChildWalletActivity.EXTRA_PARENT_WALLET_ID, walletId);
                    startActivity(intent);
                });
            }
        }
    }

    private void copyToClipboard(String value, String toastMsg) {
        android.content.ClipboardManager clipboard = (android.content.ClipboardManager) getSystemService(android.content.Context.CLIPBOARD_SERVICE);
        android.content.ClipData clip = android.content.ClipData.newPlainText("Wallet Key", value);
        if (clipboard != null) {
            clipboard.setPrimaryClip(clip);
        }
        android.widget.Toast.makeText(this, toastMsg, android.widget.Toast.LENGTH_SHORT).show();
    }

    private void handleExportFolderSelected(Uri folderUri) {
        if (folderUri == null) return;
        try {
            getContentResolver().takePersistableUriPermission(
                    folderUri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            );
        } catch (Exception ignored) {}

        executor.execute(() -> exportWalletToFolder(folderUri));
    }

    private void exportWalletToFolder(Uri folderUri) {
        try {
            File walletDir = WalletProfileStore.getWalletDir(this, walletId);
            File source = new File(walletDir, "wallet.oct");
            if (!source.exists()) {
                runOnUiThread(() -> Toast.makeText(this, "Encrypted wallet file not found", Toast.LENGTH_SHORT).show());
                return;
            }

            String treeDocumentId = DocumentsContract.getTreeDocumentId(folderUri);
            Uri treeDocumentUri = DocumentsContract.buildDocumentUriUsingTree(folderUri, treeDocumentId);
            Uri targetUri = DocumentsContract.createDocument(getContentResolver(), treeDocumentUri, "application/octet-stream", "octra_wallet");
            if (targetUri == null) {
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    Toast.makeText(this, "Failed to create export file", Toast.LENGTH_SHORT).show();
                });
                return;
            }

            try (FileInputStream input = new FileInputStream(source);
                 OutputStream output = getContentResolver().openOutputStream(targetUri, "w")) {
                if (output == null) {
                    runOnUiThread(() -> {
                        if (isFinishing() || isDestroyed()) return;
                        Toast.makeText(this, "Failed to open export destination", Toast.LENGTH_SHORT).show();
                    });
                    return;
                }
                byte[] buffer = new byte[4096];
                int len;
                while ((len = input.read(buffer)) > 0) {
                    output.write(buffer, 0, len);
                }
            }

            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                Toast.makeText(this, "Wallet exported successfully", Toast.LENGTH_LONG).show();
            });
        } catch (Exception e) {
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                Toast.makeText(this, "Export failed: " + e.getMessage(), Toast.LENGTH_SHORT).show();
            });
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        executor.shutdown();
    }
}
