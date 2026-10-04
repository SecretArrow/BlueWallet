package com.octopus.wallet;

import android.os.Bundle;
import android.annotation.SuppressLint;
import android.widget.TextView;
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.appcompat.app.AppCompatActivity;
import com.google.android.material.appbar.MaterialToolbar;

public class ExportWalletsActivity extends AppCompatActivity {
    private static final int REQUEST_EXPORT_FOLDER = 0x0E11;
    private boolean pinVerified = false;
    private boolean pendingExportAfterPin = false;

    private final ActivityResultLauncher<android.content.Intent> pinEntryLauncher =
            registerForActivityResult(new ActivityResultContracts.StartActivityForResult(), result -> {
                if (result.getResultCode() == RESULT_OK) {
                    pinVerified = true;
                    if (pendingExportAfterPin) {
                        pendingExportAfterPin = false;
                        openExportFolderPicker();
                    }
                    return;
                }
                boolean hadPending = pendingExportAfterPin;
                pendingExportAfterPin = false;
                if (!pinVerified || hadPending) {
                    finish();
                }
            });

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

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        setTheme(ThemeManager.resolveThemeRes(this));
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_export_wallet);

        MaterialToolbar toolbar = findViewById(R.id.export_toolbar);
        setSupportActionBar(toolbar);
        if (getSupportActionBar() != null) {
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
            getSupportActionBar().setDisplayShowHomeEnabled(true);
            getSupportActionBar().setTitle("Export Wallets");
        }
        toolbar.setNavigationOnClickListener(v -> finish());

        // Set info and description in full English
        TextView infoText = findViewById(R.id.export_info_text);
        TextView descText = findViewById(R.id.export_desc_text);
        infoText.setText("Export your wallets securely.");
        descText.setText("You can export your wallet data to a file for backup or transfer.");

        com.google.android.material.button.MaterialButton exportBtn = findViewById(R.id.export_wallets_button);
        exportBtn.setOnClickListener(v -> {
            if (!pinVerified) {
                requestPinVerification(true);
                return;
            }
            openExportFolderPicker();
        });

        requestPinVerification(false);
    }

    private void openExportFolderPicker() {
            android.content.Intent intent = new android.content.Intent(android.content.Intent.ACTION_OPEN_DOCUMENT_TREE);
            intent.addFlags(android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION | android.content.Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
            startActivityForResult(intent, REQUEST_EXPORT_FOLDER);
    }

    private void requestPinVerification(boolean openFolderAfterSuccess) {
        pendingExportAfterPin = openFolderAfterSuccess;
        String selectedWalletId = WalletProfileStore.getSelectedWalletId(this);
        android.content.Intent intent = new android.content.Intent(this, PinEntryActivity.class);
        intent.putExtra(PinEntryActivity.EXTRA_WALLET_ID, selectedWalletId);
        pinEntryLauncher.launch(intent);
    }

    private void exportAllWallets(android.net.Uri folderUri) {
        if (folderUri == null) {
            android.widget.Toast.makeText(this, "No folder selected", android.widget.Toast.LENGTH_SHORT).show();
            return;
        }
        java.util.List<String> walletIds = WalletProfileStore.getWalletIds(this);
        int exported = 0;
        for (String walletId : walletIds) {
            java.io.File walletDir = WalletProfileStore.getWalletDir(this, walletId);
            java.io.File source = new java.io.File(walletDir, "wallet.oct");
            if (!source.exists()) continue;
            String safeWallet = walletId.replaceAll("[^A-Za-z0-9_-]", "_");
            String fileName = safeWallet + "-wallet.oct";
            // Use the selected folder URI directly when creating documents.
            android.net.Uri targetUri = null;
            try {
                targetUri = android.provider.DocumentsContract.createDocument(getContentResolver(), folderUri, "application/octet-stream", fileName);
            } catch (Exception e) {
                continue;
            }
            if (targetUri == null) continue;
            java.io.FileInputStream input = null;
            java.io.OutputStream output = null;
            try {
                input = new java.io.FileInputStream(source);
                output = getContentResolver().openOutputStream(targetUri, "w");
                if (output == null) continue;
                byte[] buffer = new byte[4096];
                int len;
                while ((len = input.read(buffer)) > 0) {
                    output.write(buffer, 0, len);
                }
                exported++;
            } catch (Exception e) {
                // skip on error
            } finally {
                try {
                    if (input != null) input.close();
                } catch (Exception ignored) {}
                try {
                    if (output != null) output.close();
                } catch (Exception ignored) {}
            }
        }
        android.widget.Toast.makeText(this, exported + " wallet(s) exported", android.widget.Toast.LENGTH_LONG).show();
    }
    @Override
    @Deprecated
    // takeFlags is masked to READ|WRITE below; the annotation covers the
    // int-flag pattern lint cannot verify.
    @SuppressLint("WrongConstant")
    protected void onActivityResult(int requestCode, int resultCode, android.content.Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_EXPORT_FOLDER && resultCode == RESULT_OK && data != null) {
            android.net.Uri folderUri = data.getData();
            // Persist permissions so the app can write to this folder later
            try {
                final int takeFlags = data.getFlags() & (android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION | android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
                getContentResolver().takePersistableUriPermission(folderUri, takeFlags);
            } catch (Exception ignored) {
            }
            exportAllWallets(folderUri);
        }
    }
}
