package com.octopus.wallet;

import android.content.Intent;
import android.os.Bundle;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.widget.EditText;
import android.widget.TextView;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;

public class StealthSendActivity extends BaseTxActivity {
    private View loadingRow;
    private TextView statusText;
    private View submitButton;
    private EditText toInput;
    private com.google.android.material.floatingactionbutton.FloatingActionButton stealthFabMain;
    private com.google.android.material.floatingactionbutton.FloatingActionButton stealthFabScan;
    private com.google.android.material.floatingactionbutton.FloatingActionButton stealthFabTasks;
    private View stealthFabScanLabel;
    private View stealthFabTasksLabel;
    private boolean stealthFabMenuOpen = false;
    private long recommendedFee = 5000L;

    private final ActivityResultLauncher<Intent> qrScanLauncher =
            registerForActivityResult(new ActivityResultContracts.StartActivityForResult(), result -> {
                if (result.getResultCode() == RESULT_OK && result.getData() != null) {
                    String qrText = result.getData().getStringExtra(QrScanActivity.EXTRA_QR_TEXT);
                    if (qrText != null && !qrText.trim().isEmpty() && toInput != null) {
                        toInput.setText(qrText.trim());
                    }
                }
            });

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_stealth_send);
        setupToolbar(R.id.tx_toolbar, "Stealth Send");

        toInput = findViewById(R.id.stealth_to_input);
        EditText amountInput = findViewById(R.id.stealth_amount_input);
        EditText messageInput = findViewById(R.id.stealth_message_input);
        EditText customFeeInput = findViewById(R.id.stealth_custom_fee_input);
        com.google.android.material.checkbox.MaterialCheckBox customFeeCheck = findViewById(R.id.stealth_custom_fee_check);
        loadingRow = findViewById(R.id.stealth_loading_row);
        statusText = findViewById(R.id.stealth_status_text);
        submitButton = findViewById(R.id.stealth_submit_button);

        // Show available OCT balance
        loadPublicBalance(findViewById(R.id.stealth_available_balance_text));

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
            long suggested = fetchRecommendedFee(getCurrentRpcUrl(), "stealth", recommendedFee);
            recommendedFee = suggested;
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                if (customFeeInput != null && !customFeeCheck.isChecked()) {
                    customFeeInput.setText(String.valueOf(suggested));
                }
            });
        });

        setupStealthFabMenu();

        findViewById(R.id.stealth_submit_button).setOnClickListener(v -> {
            String to = toInput.getText().toString().replaceAll("\\s+", "").trim();
            String amountText = amountInput.getText().toString().trim();
            String message = messageInput.getText().toString().trim();
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

            if (to.isEmpty() || to.length() != 47 || !to.startsWith("oct")) {
                showError("Recipient address is invalid");
                return;
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

            setQueueState(true, "Queueing stealth task...");
            String taskId = StealthTaskManager.enqueueTask(getApplicationContext(), to, amountRaw, message);
            setQueueState(false, "");

            toInput.setText("");
            amountInput.setText("");
            messageInput.setText("");

            showSuccess("Stealth task queued: " + taskId);
            Intent detailIntent = new Intent(this, StealthTaskDetailActivity.class);
            detailIntent.putExtra("task_id", taskId);
            startActivity(detailIntent);
        });
    }

    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        getMenuInflater().inflate(R.menu.send_toolbar_menu, menu);
        return true;
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        if (item.getItemId() == R.id.action_scan_qr) {
            Intent intent = new Intent(this, QrScanActivity.class);
            qrScanLauncher.launch(intent);
            return true;
        }
        return super.onOptionsItemSelected(item);
    }

    private void setQueueState(boolean queueing, String message) {
        if (loadingRow != null) {
            loadingRow.setVisibility(queueing ? View.VISIBLE : View.GONE);
        }
        if (statusText != null && message != null && !message.trim().isEmpty()) {
            statusText.setText(message);
        }
        if (submitButton != null) {
            submitButton.setEnabled(!queueing);
            submitButton.setAlpha(queueing ? 0.6f : 1f);
        }
    }

    private void setupStealthFabMenu() {
        stealthFabMain = findViewById(R.id.stealth_send_fab_main);
        stealthFabScan = findViewById(R.id.stealth_send_fab_scan);
        stealthFabTasks = findViewById(R.id.stealth_send_fab_tasks);
        stealthFabScanLabel = findViewById(R.id.stealth_send_fab_scan_label);
        stealthFabTasksLabel = findViewById(R.id.stealth_send_fab_tasks_label);

        if (stealthFabMain == null || stealthFabScan == null || stealthFabTasks == null) {
            return;
        }

        stealthFabMain.setOnClickListener(v -> toggleFabMenu());
        stealthFabScan.setOnClickListener(v -> {
            closeFabMenu();
            startActivity(new Intent(this, StealthScanActivity.class));
        });
        stealthFabTasks.setOnClickListener(v -> {
            closeFabMenu();
            startActivity(new Intent(this, TransactionsManagerActivity.class));
        });
    }

    private void toggleFabMenu() {
        if (stealthFabMenuOpen) {
            closeFabMenu();
        } else {
            openFabMenu();
        }
    }

    private void openFabMenu() {
        stealthFabMenuOpen = true;
        if (stealthFabMain != null) {
            stealthFabMain.setImageResource(android.R.drawable.ic_menu_close_clear_cancel);
        }
        stealthFabScan.setVisibility(View.VISIBLE);
        stealthFabTasks.setVisibility(View.VISIBLE);
        if (stealthFabScanLabel != null) stealthFabScanLabel.setVisibility(View.VISIBLE);
        if (stealthFabTasksLabel != null) stealthFabTasksLabel.setVisibility(View.VISIBLE);
        stealthFabScan.animate().translationY(-getResources().getDimensionPixelSize(R.dimen.fab_offset_1)).setDuration(200).start();
        stealthFabTasks.animate().translationY(-getResources().getDimensionPixelSize(R.dimen.fab_offset_2)).setDuration(200).start();
        if (stealthFabScanLabel != null) {
            stealthFabScanLabel.animate().translationY(-getResources().getDimensionPixelSize(R.dimen.fab_offset_1)).setDuration(200).start();
        }
        if (stealthFabTasksLabel != null) {
            stealthFabTasksLabel.animate().translationY(-getResources().getDimensionPixelSize(R.dimen.fab_offset_2)).setDuration(200).start();
        }
    }

    private void closeFabMenu() {
        stealthFabMenuOpen = false;
        if (stealthFabMain != null) {
            stealthFabMain.setImageResource(android.R.drawable.ic_input_add);
        }
        if (stealthFabScan != null) {
            stealthFabScan.animate().translationY(0).setDuration(200)
                    .withEndAction(() -> stealthFabScan.setVisibility(View.GONE)).start();
        }
        if (stealthFabTasks != null) {
            stealthFabTasks.animate().translationY(0).setDuration(200)
                    .withEndAction(() -> stealthFabTasks.setVisibility(View.GONE)).start();
        }
        if (stealthFabScanLabel != null) {
            stealthFabScanLabel.animate().translationY(0).setDuration(200)
                    .withEndAction(() -> stealthFabScanLabel.setVisibility(View.GONE)).start();
        }
        if (stealthFabTasksLabel != null) {
            stealthFabTasksLabel.animate().translationY(0).setDuration(200)
                    .withEndAction(() -> stealthFabTasksLabel.setVisibility(View.GONE)).start();
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        if (stealthFabMenuOpen) {
            closeFabMenu();
        }
    }
}
