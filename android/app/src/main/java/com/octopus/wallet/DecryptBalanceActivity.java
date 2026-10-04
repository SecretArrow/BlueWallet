package com.octopus.wallet;

import android.content.Intent;
import android.os.Bundle;
import android.view.View;
import android.widget.EditText;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;

public class DecryptBalanceActivity extends BaseTxActivity {
    private View submitButton;
    private long recommendedFee = 3000L;

    private final ActivityResultLauncher<Intent> progressLauncher =
            registerForActivityResult(new ActivityResultContracts.StartActivityForResult(), result -> {
                if (result.getResultCode() == RESULT_OK) {
                    // Auto-refresh balance in background (silent, no loading indicator)
                    refreshBalanceSilent();
                    finish();
                }
            });

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_decrypt_balance);
        setupToolbar(R.id.tx_toolbar, "Decrypt Balance");

        EditText amountInput = findViewById(R.id.decrypt_amount_input);
        EditText customFeeInput = findViewById(R.id.decrypt_custom_fee_input);
        com.google.android.material.checkbox.MaterialCheckBox customFeeCheck = findViewById(R.id.decrypt_custom_fee_check);
        submitButton = findViewById(R.id.decrypt_submit_button);

        // Show available encrypted OCT balance (source for decryption)
        loadEncryptedBalance(findViewById(R.id.decrypt_available_balance_text));

        if (customFeeInput != null) {
            customFeeInput.setText(String.valueOf(recommendedFee));
        }

        customFeeCheck.setOnCheckedChangeListener((buttonView, isChecked) -> {
            customFeeInput.setEnabled(isChecked);
            if (!isChecked) {
                customFeeInput.setText(String.valueOf(recommendedFee));
            }
        });

        ioExecutor().execute(() -> {
            long suggested = fetchRecommendedFee(getCurrentRpcUrl(), "decrypt", recommendedFee);
            recommendedFee = suggested;
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                if (customFeeInput != null && !customFeeCheck.isChecked()) {
                    customFeeInput.setText(String.valueOf(suggested));
                }
            });
        });

        findViewById(R.id.decrypt_submit_button).setOnClickListener(v -> {
            String amountText = amountInput.getText().toString().trim();
            String customFeeText = customFeeInput.getText().toString().trim();

            if (customFeeCheck.isChecked()) {
                try {
                    long fee = Long.parseLong(customFeeText.isEmpty() ? "0" : customFeeText);
                    if (fee <= 0) {
                        showError("Custom gas fee must be greater than 0");
                        return;
                    }
                } catch (Exception e) {
                    showError("Custom gas fee is invalid");
                    return;
                }
            }

            long amountRaw;
            try {
                amountRaw = new java.math.BigDecimal(amountText)
                        .multiply(java.math.BigDecimal.valueOf(1_000_000))
                        .setScale(0, java.math.RoundingMode.HALF_UP).longValue();
            } catch (Exception e) {
                showError("Amount is invalid");
                return;
            }
            if (amountRaw <= 0) {
                showError("Amount must be greater than 0");
                return;
            }

            String currentTxId = "tx_dec_" + System.currentTimeMillis();
            TxForegroundService.startTx(this, TxForegroundService.ACTION_DECRYPT,
                    currentTxId, null, amountRaw, null);

            Intent progressIntent = new Intent(this, TxProgressActivity.class);
            progressIntent.putExtra(TxProgressActivity.EXTRA_TX_ID, currentTxId);
            progressIntent.putExtra(TxProgressActivity.EXTRA_TX_TYPE, TxForegroundService.ACTION_DECRYPT);
            progressLauncher.launch(progressIntent);

            amountInput.setText("");
        });

        com.google.android.material.floatingactionbutton.FloatingActionButton txManagerFab =
                findViewById(R.id.decrypt_fab_tx_manager);
        if (txManagerFab != null) {
            txManagerFab.setOnClickListener(v ->
                    startActivity(new Intent(this, TransactionsManagerActivity.class)));
        }
    }

    /**
     * Refreshes balance in the background without showing any loading indicator.
     */
    private void refreshBalanceSilent() {
        ioExecutor().execute(() -> {
            try {
                String rpcUrl = getCurrentRpcUrl();
                String address = getCurrentWalletAddress();
                if (rpcUrl != null && address != null) {
                    repo().fetchBalance(rpcUrl, address);
                }
            } catch (Exception e) {
                // Silently ignore — balance will update on next foreground refresh
            }
        });
    }

    /**
     * Returns the current wallet address from the selected wallet profile.
     */
    private String getCurrentWalletAddress() {
        try {
            String walletId = WalletProfileStore.getSelectedWalletId(this);
            if (walletId != null) {
                return WalletAddressStore.getAddress(this, walletId);
            }
        } catch (Exception e) {
            // Ignore errors
        }
        return null;
    }
}
