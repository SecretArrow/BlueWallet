package com.octopus.wallet;

import android.content.Intent;
import android.os.Bundle;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.appcompat.app.AppCompatActivity;
import androidx.biometric.BiometricManager;
import androidx.biometric.BiometricPrompt;
import androidx.core.content.ContextCompat;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.concurrent.Executor;

public class UnlockActivity extends AppCompatActivity {

    private static final String PREFS_BIOMETRIC         = "biometric_prefs";
    private static final String KEY_BIOMETRIC_ENABLED   = "biometric_enabled";
    private static final String KEY_BIOMETRIC_DECIDED   = "biometric_decided";

    private EditText pinInput;

    private final ActivityResultLauncher<Intent> biometricEnrollmentLauncher =
            registerForActivityResult(new ActivityResultContracts.StartActivityForResult(), result -> {
                if (result.getResultCode() == RESULT_OK) {
                    setBiometricEnabled(true);
                }
                setBiometricDecided(true);
                proceedToMain();
            });

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        setTheme(resolveThemeRes());
        super.onCreate(savedInstanceState);
        // Prevent screenshots on the unlock screen
        getWindow().setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE);
        setContentView(R.layout.activity_unlock);

        // Apply window insets so content never overlaps nav bar / gesture strip
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(android.R.id.content), (v, insets) -> {
            androidx.core.graphics.Insets navBars =
                    insets.getInsets(WindowInsetsCompat.Type.navigationBars());
            androidx.core.graphics.Insets statusBars =
                    insets.getInsets(WindowInsetsCompat.Type.statusBars());
            v.setPadding(v.getPaddingLeft(), statusBars.top, v.getPaddingRight(), navBars.bottom);
            return insets;
        });

        initViews();

        // Run security check once per launch
        SecurityChecker.performStartupCheck(this);

        // Try biometric if available and previously enabled
        if (isBiometricEnabled() && isBiometricAvailable()) {
            showBiometricPrompt();
        }
    }

    private int resolveThemeRes() {
        return ThemeManager.resolveThemeRes(this);
    }

    // ── View setup ─────────────────────────────────────────────────────────

    private void initViews() {
        pinInput     = findViewById(R.id.unlock_pin_input);
        Button unlockButton = findViewById(R.id.unlock_button);

        unlockButton.setOnClickListener(v -> doUnlock());

        Button biometricButton = findViewById(R.id.unlock_biometric_button);
        TextView biometricHint = findViewById(R.id.unlock_biometric_hint);

        if (biometricButton != null) {
            if (isBiometricAvailable()) {
                biometricButton.setVisibility(android.view.View.VISIBLE);
                biometricButton.setOnClickListener(v -> showBiometricPrompt());
                if (biometricHint != null) {
                    biometricHint.setVisibility(android.view.View.VISIBLE);
                    biometricHint.setText(isBiometricEnabled()
                            ? "Biometric unlock is enabled — use fingerprint/face or enter PIN below."
                            : "Enter your PIN. You can enable biometric unlock after logging in.");
                }
            } else {
                biometricButton.setVisibility(android.view.View.GONE);
                if (biometricHint != null) biometricHint.setVisibility(android.view.View.GONE);
            }
        }
    }

    // ── PIN unlock ─────────────────────────────────────────────────────────

    private void doUnlock() {
        String pin = pinInput.getText().toString();

        if (pin.length() != 6) {
            showError("PIN must be exactly 6 digits");
            return;
        }
        if (!pin.matches("\\d{6}")) {
            showError("PIN must contain only digits");
            return;
        }

        if (unlockWithPin(pin)) {
            // Offer biometric enrollment once after successful PIN unlock
            if (isBiometricAvailable() && !isBiometricEnableDecided()) {
                offerBiometricEnrollment();
            } else {
                proceedToMain();
            }
        }
    }

    /**
     * @return true if the wallet was unlocked successfully, false otherwise.
     */
    private boolean unlockWithPin(String pin) {
        try {
            String result = OctraNative.getInstance().unlockWallet(pin);
            JSONObject json = new JSONObject(result);
            if (json.has("error")) {
                showError(json.getString("error"));
                return false;
            }
            PinStore.setDefaultPin(this, pin);
            SessionLockActivity.recordActivity(this);
            String address  = json.getString("address");
            String walletId = WalletProfileStore.getSelectedWalletId(this);
            WalletAddressStore.putAddress(getApplicationContext(), walletId, address);
            return true;
        } catch (JSONException e) {
            showError("Failed to unlock wallet");
            return false;
        }
    }

    // ── Biometric auth ─────────────────────────────────────────────────────

    private void showBiometricPrompt() {
        if (!isBiometricAvailable()) return;

        Executor executor = ContextCompat.getMainExecutor(this);
        BiometricPrompt prompt = new BiometricPrompt(this, executor,
                new BiometricPrompt.AuthenticationCallback() {
                    @Override
                    public void onAuthenticationSucceeded(BiometricPrompt.AuthenticationResult result) {
                        super.onAuthenticationSucceeded(result);
                        // Re-use stored PIN silently to unlock native wallet
                        String pin = PinStore.getDefaultPin(UnlockActivity.this);
                        if (pin.matches("\\d{6}")) {
                            if (unlockWithPin(pin)) {
                                proceedToMain();
                            }
                        } else {
                            showError("No PIN stored — please enter your PIN manually");
                        }
                    }

                    @Override
                    public void onAuthenticationError(int errorCode, CharSequence errString) {
                        super.onAuthenticationError(errorCode, errString);
                        if (errorCode != BiometricPrompt.ERROR_USER_CANCELED
                                && errorCode != BiometricPrompt.ERROR_NEGATIVE_BUTTON) {
                            Toast.makeText(UnlockActivity.this,
                                    "Biometric error: " + errString, Toast.LENGTH_SHORT).show();
                        }
                    }

                    @Override
                    public void onAuthenticationFailed() {
                        super.onAuthenticationFailed();
                        Toast.makeText(UnlockActivity.this,
                                "Biometric not recognised — enter your PIN below.",
                                Toast.LENGTH_SHORT).show();
                    }
                });

        BiometricPrompt.PromptInfo promptInfo = new BiometricPrompt.PromptInfo.Builder()
                .setTitle("Octra Wallet")
                .setSubtitle("Verify your identity to unlock")
                .setNegativeButtonText("Use PIN")
                .setAllowedAuthenticators(
                        BiometricManager.Authenticators.BIOMETRIC_STRONG
                        | BiometricManager.Authenticators.BIOMETRIC_WEAK)
                .build();

        prompt.authenticate(promptInfo);
    }

    private void offerBiometricEnrollment() {
        Intent intent = new Intent(this, ConfirmActionActivity.class);
        intent.putExtra(ConfirmActionActivity.EXTRA_TITLE, "Enable Biometric Unlock?");
        intent.putExtra(ConfirmActionActivity.EXTRA_MESSAGE,
                "Use fingerprint or face recognition to unlock faster next time.");
        intent.putExtra(ConfirmActionActivity.EXTRA_POSITIVE, "Enable");
        intent.putExtra(ConfirmActionActivity.EXTRA_NEGATIVE, "Not Now");
        intent.putExtra(ConfirmActionActivity.EXTRA_REQUIRE_EXPLICIT, true);
        biometricEnrollmentLauncher.launch(intent);
    }

    // ── Navigation ─────────────────────────────────────────────────────────

    private void proceedToMain() {
        startActivity(new Intent(this, MainActivity.class));
        finish();
    }

    // ── Biometric prefs helpers ────────────────────────────────────────────

    private boolean isBiometricAvailable() {
        BiometricManager bm = BiometricManager.from(this);
        int can = bm.canAuthenticate(
                BiometricManager.Authenticators.BIOMETRIC_STRONG
                | BiometricManager.Authenticators.BIOMETRIC_WEAK);
        return can == BiometricManager.BIOMETRIC_SUCCESS;
    }

    private boolean isBiometricEnabled() {
        return getSharedPreferences(PREFS_BIOMETRIC, MODE_PRIVATE)
                .getBoolean(KEY_BIOMETRIC_ENABLED, false);
    }

    private void setBiometricEnabled(boolean enabled) {
        getSharedPreferences(PREFS_BIOMETRIC, MODE_PRIVATE)
                .edit().putBoolean(KEY_BIOMETRIC_ENABLED, enabled).apply();
    }

    private boolean isBiometricEnableDecided() {
        return getSharedPreferences(PREFS_BIOMETRIC, MODE_PRIVATE)
                .getBoolean(KEY_BIOMETRIC_DECIDED, false);
    }

    private void setBiometricDecided(boolean decided) {
        getSharedPreferences(PREFS_BIOMETRIC, MODE_PRIVATE)
                .edit().putBoolean(KEY_BIOMETRIC_DECIDED, decided).apply();
    }

    // ── Error helper ───────────────────────────────────────────────────────

    private void showError(String message) {
        ErrorDisplayHelper.showError(this, "Unlock Failed", message);
    }
}
