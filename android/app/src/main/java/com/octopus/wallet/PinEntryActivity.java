package com.octopus.wallet;

import android.content.Intent;
import android.os.Bundle;
import android.widget.EditText;
import android.widget.Toast;

import com.google.android.material.appbar.MaterialToolbar;

public class PinEntryActivity extends BaseTxActivity {

    public static final String EXTRA_WALLET_ID = "wallet_id";
    public static final String EXTRA_PIN = "pin";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        setTheme(ThemeManager.resolveThemeRes(this));
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_pin_entry);
        setupToolbar(R.id.pin_entry_toolbar, "Enter PIN");

        String walletId = getIntent().getStringExtra(EXTRA_WALLET_ID);
        if (walletId == null || walletId.isEmpty()) {
            walletId = WalletProfileStore.getSelectedWalletId(this);
        }
        final String finalWalletId = walletId;

        EditText pinInput = findViewById(R.id.pin_entry_input);

        findViewById(R.id.pin_entry_submit).setOnClickListener(v -> {
            String pin = pinInput.getText() == null ? "" : pinInput.getText().toString().trim();
            if (!pin.matches("\\d{6}")) {
                Toast.makeText(this, "PIN must be 6 digits", Toast.LENGTH_SHORT).show();
                return;
            }
            if (!WalletPinVerifier.verify(this, finalWalletId, pin)) {
                Toast.makeText(this, "Invalid PIN", Toast.LENGTH_SHORT).show();
                return;
            }
            Intent result = new Intent();
            result.putExtra(EXTRA_PIN, pin);
            result.putExtra(EXTRA_WALLET_ID, finalWalletId);
            setResult(RESULT_OK, result);
            finish();
        });
    }
}
