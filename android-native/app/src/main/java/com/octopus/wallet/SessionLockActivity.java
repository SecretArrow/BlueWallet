package com.octopus.wallet;

import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.widget.RadioButton;
import android.widget.RadioGroup;

public class SessionLockActivity extends BaseTxActivity {

    public static final String PREFS_NAME = "session_prefs";
    public static final String KEY_LOCK_MINUTES = "auto_lock_minutes";
    public static final String KEY_LAST_ACTIVE = "last_active_time";

    private RadioGroup radioGroup;
    private int savedMinutes;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_session_lock);
        setupToolbar(R.id.session_toolbar, "Session");

        radioGroup = findViewById(R.id.session_lock_radio_group);

        SharedPreferences prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
        savedMinutes = prefs.getInt(KEY_LOCK_MINUTES, 0);

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

            prefs.edit().putInt(KEY_LOCK_MINUTES, minutes).apply();

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
        // Default to Never
        RadioButton never = findViewById(R.id.session_lock_never);
        if (never != null) never.setChecked(true);
    }

    /**
     * Record the current time as the last user interaction time.
     */
    public static void recordActivity(android.content.Context context) {
        context.getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                .edit()
                .putLong(KEY_LAST_ACTIVE, System.currentTimeMillis())
                .apply();
    }

    /**
     * Check whether the session has expired.
     * Returns true if the app should be locked.
     */
    public static boolean isSessionExpired(android.content.Context context) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
        int lockMinutes = prefs.getInt(KEY_LOCK_MINUTES, 0);
        long lastActive = prefs.getLong(KEY_LAST_ACTIVE, 0);
        return isExpiredAt(lastActive, lockMinutes, System.currentTimeMillis());
    }

    /**
     * Pure session-expiry decision (no clock/Context — unit-tested).
     * Never lock when disabled (≤0); always lock when never recorded;
     * long arithmetic is overflow-safe for any int minutes.
     */
    static boolean isExpiredAt(long lastActiveMs, int lockMinutes, long nowMs) {
        if (lockMinutes <= 0) return false; // Never lock
        if (lastActiveMs <= 0) return true; // Never recorded, force lock
        long elapsed = nowMs - lastActiveMs;
        if (elapsed < 0) return false; // Clock moved backwards — fail open briefly
        long timeoutMs = (long) lockMinutes * 60L * 1000L;
        return elapsed >= timeoutMs;
    }
}
