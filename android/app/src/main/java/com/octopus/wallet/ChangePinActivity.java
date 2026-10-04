package com.octopus.wallet;

import android.os.Bundle;
import android.widget.EditText;

import org.json.JSONObject;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class ChangePinActivity extends BaseTxActivity {

    private final ExecutorService executor = Executors.newSingleThreadExecutor();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        setTheme(ThemeManager.resolveThemeRes(this));
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_change_pin);
        setupToolbar(R.id.change_pin_toolbar, "Change PIN");

        EditText currentPinInput = findViewById(R.id.change_pin_current_input);
        EditText newPinInput = findViewById(R.id.change_pin_new_input);
        EditText confirmPinInput = findViewById(R.id.change_pin_confirm_input);

        findViewById(R.id.change_pin_submit_button).setOnClickListener(v -> {
            String currentPin = currentPinInput.getText() == null ? "" : currentPinInput.getText().toString().trim();
            String newPin = newPinInput.getText() == null ? "" : newPinInput.getText().toString().trim();
            String confirmPin = confirmPinInput.getText() == null ? "" : confirmPinInput.getText().toString().trim();

            if (!currentPin.matches("\\d{6}")) {
                showError("Current PIN must be 6 digits");
                return;
            }
            if (!newPin.matches("\\d{6}")) {
                showError("New PIN must be 6 digits");
                return;
            }
            if (!newPin.equals(confirmPin)) {
                showError("PIN confirmation does not match");
                return;
            }

            executor.execute(() -> changePin(currentPin, newPin));
        });
    }

    private void changePin(String currentPin, String newPin) {
        try {
            String result = OctraNative.getInstance().changePin(currentPin, newPin);
            JSONObject json = new JSONObject(result);
            if (json.has("error")) {
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    showError(json.optString("error", "Failed to change PIN"));
                });
                return;
            }
            PinStore.setDefaultPin(this, newPin);
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                showSuccess("PIN changed successfully");
                finish();
            });
        } catch (Exception e) {
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                showError("Failed to change PIN");
            });
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        executor.shutdown();
    }
}
