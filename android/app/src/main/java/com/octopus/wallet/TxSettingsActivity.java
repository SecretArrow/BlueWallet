package com.octopus.wallet;

import android.os.Bundle;
import android.widget.EditText;
import android.widget.Toast;

public class TxSettingsActivity extends BaseTxActivity {

    private EditText inputInterval;
    private EditText inputThresholdSend;
    private EditText inputThresholdAdvanced;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        setTheme(ThemeManager.resolveThemeRes(this));
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_tx_settings);
        setupToolbar(R.id.polling_settings_toolbar, "Polling Settings");

        inputInterval = findViewById(R.id.input_polling_interval);
        inputThresholdSend = findViewById(R.id.input_threshold_send);
        inputThresholdAdvanced = findViewById(R.id.input_threshold_advanced);

        loadSettings();

        findViewById(R.id.btn_save_polling).setOnClickListener(v -> saveSettings());
    }

    private void loadSettings() {
        long intervalS = PollingSettingsStore.getIntervalMs(this) / 1000;
        long thresholdSendM = PollingSettingsStore.getThresholdSendMs(this) / 60000;
        long thresholdAdvancedM = PollingSettingsStore.getThresholdAdvancedMs(this) / 60000;

        if (inputInterval != null) inputInterval.setText(String.valueOf(intervalS));
        if (inputThresholdSend != null) inputThresholdSend.setText(String.valueOf(thresholdSendM));
        if (inputThresholdAdvanced != null) inputThresholdAdvanced.setText(String.valueOf(thresholdAdvancedM));
    }

    private void saveSettings() {
        if (inputInterval == null || inputThresholdSend == null || inputThresholdAdvanced == null) {
            return;
        }
        try {
            long intervalS = Long.parseLong(inputInterval.getText().toString());
            long thresholdSendM = Long.parseLong(inputThresholdSend.getText().toString());
            long thresholdAdvancedM = Long.parseLong(inputThresholdAdvanced.getText().toString());

            if (intervalS < 1) {
                showError("Interval must be at least 1 second");
                return;
            }
            if (thresholdSendM < 1 || thresholdAdvancedM < 1) {
                showError("Timeout must be at least 1 minute");
                return;
            }

            PollingSettingsStore.setIntervalMs(this, intervalS * 1000);
            PollingSettingsStore.setThresholdSendMs(this, thresholdSendM * 60000);
            PollingSettingsStore.setThresholdAdvancedMs(this, thresholdAdvancedM * 60000);

            android.content.Intent result = new android.content.Intent();
            result.putExtra("settings_changed", true);
            setResult(RESULT_OK, result);

            showSuccess("Polling settings saved");
            finish();
        } catch (NumberFormatException e) {
            showError("Please enter valid numbers");
        }
    }
}
