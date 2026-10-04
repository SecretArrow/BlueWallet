package com.octopus.wallet;

import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.widget.RadioButton;
import android.widget.RadioGroup;

public class AutoScanActivity extends BaseTxActivity {

    public static final String PREFS_NAME = "auto_scan_prefs";
    public static final String KEY_SCAN_MINUTES = "auto_scan_minutes";

    private RadioGroup radioGroup;
    private int savedMinutes;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_auto_scan);
        setupToolbar(R.id.auto_scan_toolbar, "Auto Scan");

        radioGroup = findViewById(R.id.auto_scan_radio_group);

        SharedPreferences prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
        savedMinutes = prefs.getInt(KEY_SCAN_MINUTES, 0);

        selectRadioByMinutes(savedMinutes);

        radioGroup.setOnCheckedChangeListener((group, checkedId) -> {
            RadioButton selected = findViewById(checkedId);
            if (selected == null) return;
            String tag = (String) selected.getTag();
            int minutes = 0;
            try {
                minutes = Integer.parseInt(tag);
            } catch (Exception ignored) {
            }

            prefs.edit().putInt(KEY_SCAN_MINUTES, minutes).apply();

            if (minutes != savedMinutes) {
                savedMinutes = minutes;
                Intent result = new Intent();
                result.putExtra("settings_changed", true);
                setResult(RESULT_OK, result);
            }
        });
    }

    private void selectRadioByMinutes(int minutes) {
        for (int i = 0; i < radioGroup.getChildCount(); i++) {
            RadioButton rb = (RadioButton) radioGroup.getChildAt(i);
            String tag = (String) rb.getTag();
            try {
                if (Integer.parseInt(tag) == minutes) {
                    rb.setChecked(true);
                    return;
                }
            } catch (Exception ignored) {
            }
        }
        RadioButton never = findViewById(R.id.auto_scan_never);
        if (never != null) never.setChecked(true);
    }

    /**
     * Get the configured scan interval in minutes (0 = disabled).
     */
    public static int getScanIntervalMinutes(android.content.Context context) {
        return context.getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                .getInt(KEY_SCAN_MINUTES, 0);
    }
}
