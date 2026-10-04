package com.octopus.wallet;

import android.content.Intent;
import android.os.Bundle;
import android.widget.EditText;

import com.google.android.material.appbar.MaterialToolbar;
import com.google.android.material.button.MaterialButton;

public class WalletFilePinActivity extends BaseTxActivity {

    public static final String EXTRA_FILE_PIN = "file_pin";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_wallet_file_pin);
        setupToolbar(R.id.wallet_file_pin_toolbar, "Wallet File PIN");

        EditText pinInput = findViewById(R.id.wallet_file_pin_input);
        MaterialButton continueButton = findViewById(R.id.wallet_file_pin_button);

        continueButton.setOnClickListener(v -> {
            String pin = pinInput.getText() == null ? "" : pinInput.getText().toString().trim();
            if (!pin.matches("\\d{6}")) {
                showError("PIN must be 6 digits");
                return;
            }
            Intent result = new Intent();
            result.putExtra(EXTRA_FILE_PIN, pin);
            setResult(RESULT_OK, result);
            finish();
        });
    }
}
