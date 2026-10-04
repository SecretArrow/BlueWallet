package com.octopus.wallet;

import android.content.Intent;
import android.os.Bundle;
import android.widget.EditText;
import android.widget.TextView;

import com.google.android.material.appbar.MaterialToolbar;
import com.google.android.material.button.MaterialButton;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class ConfirmDeleteWalletActivity extends BaseTxActivity {

    public static final String EXTRA_WALLET_ID = "wallet_id";

    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private MaterialButton removeButton;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_confirm_delete_wallet);
        setupToolbar(R.id.confirm_delete_toolbar, "Remove Wallet");

        String walletId = getIntent().getStringExtra(EXTRA_WALLET_ID);
        if (walletId == null || walletId.isEmpty()) {
            finish();
            return;
        }

        TextView walletNameText = findViewById(R.id.confirm_delete_wallet_name);
        walletNameText.setText(walletId);

        EditText pinInput = findViewById(R.id.confirm_delete_pin_input);
        removeButton = findViewById(R.id.confirm_delete_remove_button);

        removeButton.setOnClickListener(v -> {
            String pin = pinInput.getText() == null ? "" : pinInput.getText().toString().trim();
            if (!pin.matches("\\d{6}")) {
                showError("PIN must be 6 digits");
                return;
            }
            removeButton.setEnabled(false);
            removeButton.setAlpha(0.6f);
            executor.execute(() -> {
                boolean valid = WalletPinVerifier.verify(this, walletId, pin);
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    removeButton.setEnabled(true);
                    removeButton.setAlpha(1f);
                    if (!valid) {
                        showError("Incorrect PIN");
                        return;
                    }
                    Intent result = new Intent();
                    result.putExtra(EXTRA_WALLET_ID, walletId);
                    setResult(RESULT_OK, result);
                    finish();
                });
            });
        });
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        executor.shutdown();
    }
}
