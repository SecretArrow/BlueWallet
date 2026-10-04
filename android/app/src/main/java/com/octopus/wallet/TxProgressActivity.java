package com.octopus.wallet;

import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.widget.ProgressBar;
import android.widget.TextView;
import java.util.Locale;
import java.util.regex.Pattern;

import org.json.JSONObject;

import com.google.android.material.button.MaterialButton;
import com.google.android.material.card.MaterialCardView;

public class TxProgressActivity extends BaseTxActivity {

    public static final String EXTRA_TX_ID = "tx_id";
    public static final String EXTRA_TX_TYPE = "tx_type";

    private ProgressBar spinner;
    private TextView statusIcon;
    private TextView statusLabel;
    private TextView statusMessage;
    private MaterialCardView detailCard;
    private TextView typeText;
    private TextView hashText;
    private TextView resultText;
    private MaterialButton closeButton;

    private String txId;
    private String txType;
    private boolean isFinished = false;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final Runnable pollRunnable = this::pollTaskState;
    private boolean hasShownTimeoutPrompt = false;

    private final TxForegroundService.TxCallback txCallback = new TxForegroundService.TxCallback() {
        @Override
        public void onTxProgress(String id, String message) {
            if (!id.equals(txId)) return;
            mainHandler.post(() -> {
                if (isFinishing() || isDestroyed()) return;
                showProgress(message);
            });
        }

        @Override
        public void onTxSuccess(String id, String message, String txHash) {
            if (!id.equals(txId)) return;
            mainHandler.post(() -> {
                if (isFinishing() || isDestroyed()) return;
                showSuccess(message, txHash);
            });
        }

        @Override
        public void onTxFailed(String id, String message) {
            if (!id.equals(txId)) return;
            mainHandler.post(() -> {
                if (isFinishing() || isDestroyed()) return;
                showFailure(message);
            });
        }

        @Override
        public void onTxTimeout(String id, String message) {
            if (!id.equals(txId)) return;
            mainHandler.post(() -> {
                if (isFinishing() || isDestroyed()) return;
                showTimeoutPrompt(message);
            });
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_tx_progress);

        txId = getIntent().getStringExtra(EXTRA_TX_ID);
        txType = getIntent().getStringExtra(EXTRA_TX_TYPE);
        if (txId == null) txId = "";
        if (txType == null) txType = "send";
        if (!txId.trim().isEmpty()) {
            TxTaskStore.markTaskOpened(getApplicationContext(), txId);
        }
        clearResultNotification();
        TxForegroundService.clearTaskNotifications(this, txId);

        String titleText;
        switch (txType) {
            case TxForegroundService.ACTION_ENCRYPT:
                titleText = "Encrypt Balance";
                break;
            case TxForegroundService.ACTION_DECRYPT:
                titleText = "Decrypt Balance";
                break;
            case TxForegroundService.ACTION_STEALTH:
                titleText = "Stealth Send";
                break;
            case TxForegroundService.ACTION_TOKEN_SEND:
                titleText = "Token Transfer";
                break;
            default:
                titleText = "Send Transaction";
                break;
        }

        setupToolbar(R.id.tx_progress_toolbar, titleText);

        spinner = findViewById(R.id.tx_progress_spinner);
        statusIcon = findViewById(R.id.tx_progress_icon);
        statusLabel = findViewById(R.id.tx_progress_status);
        statusMessage = findViewById(R.id.tx_progress_message);
        detailCard = findViewById(R.id.tx_progress_detail_card);
        typeText = findViewById(R.id.tx_progress_type);
        hashText = findViewById(R.id.tx_progress_hash);
        resultText = findViewById(R.id.tx_progress_result);
        closeButton = findViewById(R.id.tx_progress_close_button);

        typeText.setText(formatType(txType));

        closeButton.setOnClickListener(v -> {
            if (isFinished) {
                finish();
            }
        });

        // Register callback - the service executor will deliver progress/success/fail here
        TxForegroundService.setCallback(txCallback);

        TxTaskStore.TaskItem task = TxTaskStore.getTaskById(getApplicationContext(), txId);
        if (task != null && !TxTaskStore.STATUS_SUCCESS.equals(task.status) && !TxTaskStore.STATUS_FAILED.equals(task.status)) {
            TxForegroundService.startRecovery(this);
        }

        pollTaskState();
    }

    @Override
    protected void onResume() {
        super.onResume();
        // Re-register callback when returning to this activity
        if (!isFinished) {
            TxForegroundService.setCallback(txCallback);
            mainHandler.removeCallbacks(pollRunnable);
            mainHandler.post(pollRunnable);
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        mainHandler.removeCallbacks(pollRunnable);
    }

    private void pollTaskState() {
        if (txId == null || txId.trim().isEmpty()) {
            return;
        }

        TxTaskStore.TaskItem task = TxTaskStore.getTaskById(getApplicationContext(), txId);
        if (task != null) {
            if (txType == null || txType.trim().isEmpty()) {
                txType = task.type;
                typeText.setText(formatType(txType));
            }

            if (TxTaskStore.STATUS_SUCCESS.equals(task.status)) {
                showSuccess(task.progressMessage, task.txHash);
            } else if (TxTaskStore.STATUS_FAILED.equals(task.status)) {
                String failMessage = task.errorMessage == null || task.errorMessage.trim().isEmpty()
                        ? task.progressMessage
                        : task.errorMessage;
                showFailure(failMessage);
            } else {
                String progress = task.progressMessage == null || task.progressMessage.trim().isEmpty()
                        ? "Processing transaction..."
                        : task.progressMessage;
                showProgress(progress);
                if (task.txHash != null && !task.txHash.trim().isEmpty()) {
                    hashText.setText(task.txHash);
                    detailCard.setVisibility(View.VISIBLE);
                    resultText.setText(progress);
                }
            }
        }

        if (!isFinished) {
            checkTimeoutPrompt(task);
            mainHandler.postDelayed(pollRunnable, 1000L);
        }
    }

    private void checkTimeoutPrompt(TxTaskStore.TaskItem task) {
        if (task == null || hasShownTimeoutPrompt || isFinished) return;

        long limit;
        if (TxForegroundService.ACTION_SEND.equals(txType) || 
            TxForegroundService.ACTION_TOKEN_SEND.equals(txType)) {
            limit = PollingSettingsStore.getThresholdSendMs(this);
        } else {
            limit = PollingSettingsStore.getThresholdAdvancedMs(this);
        }
        
        long elapsed = System.currentTimeMillis() - task.createdAt;
        if (elapsed > limit) {
            hasShownTimeoutPrompt = true;
            showTimeoutPrompt("This transaction is taking longer than usual. Would you like to keep waiting or return home?");
        }
    }

    private void showProgress(String message) {
        spinner.setVisibility(View.VISIBLE);
        statusIcon.setVisibility(View.GONE);
        statusLabel.setText("Processing...");
        statusMessage.setText(message != null ? message : "Preparing transaction...");
        detailCard.setVisibility(View.GONE);
        closeButton.setVisibility(View.GONE);
    }

    private void showSuccess(String message, String txHash) {
        isFinished = true;
        TxForegroundService.clearTaskNotifications(this, txId);
        spinner.setVisibility(View.GONE);
        statusIcon.setVisibility(View.VISIBLE);
        statusIcon.setText("\u2714");
        statusIcon.setTextColor(0xFF4CAF50);
        statusLabel.setText("Success");
        statusMessage.setText(message != null ? message : "Transaction submitted");

        detailCard.setVisibility(View.VISIBLE);
        hashText.setText(txHash != null && !txHash.isEmpty() ? txHash : "-");
        resultText.setText("Transaction submitted successfully");

        closeButton.setVisibility(View.VISIBLE);
        closeButton.setText("Done");

        Intent result = new Intent();
        result.putExtra("tx_hash", txHash != null ? txHash : "");
        result.putExtra("tx_status", "success");
        result.putExtra("tx_type", txType == null ? "" : txType);
        try {
            TxTaskStore.TaskItem task = TxTaskStore.getTaskById(getApplicationContext(), txId);
            if (task != null) {
                result.putExtra("tx_to", task.to == null ? "" : task.to);
                long amountRaw = 0L;
                try {
                    amountRaw = Long.parseLong(task.amountRaw == null ? "0" : task.amountRaw);
                } catch (Exception ignored) {
                }
                result.putExtra("tx_amount_raw", amountRaw);
            }
        } catch (Exception ignored) {
        }
        String tokenSymbol = resolveTokenSymbolForResult();
        if (tokenSymbol != null && !tokenSymbol.trim().isEmpty()) {
            result.putExtra("tx_token_symbol", tokenSymbol.trim());
        }
        setResult(RESULT_OK, result);
    }

    private void showFailure(String message) {
        isFinished = true;
        TxForegroundService.clearTaskNotifications(this, txId);
        spinner.setVisibility(View.GONE);
        statusIcon.setVisibility(View.VISIBLE);
        statusIcon.setText("\u2718");
        statusIcon.setTextColor(0xFFF44336);
        statusLabel.setText("Failed");
        statusMessage.setText(message != null ? message : "Transaction failed");

        detailCard.setVisibility(View.VISIBLE);
        hashText.setText("-");
        resultText.setText(message != null ? message : "Transaction failed");

        closeButton.setVisibility(View.VISIBLE);
        closeButton.setText("Close");

        setResult(RESULT_CANCELED);
    }

    private void showTimeoutPrompt(String message) {
        // Only show if not already finished
        if (isFinished) return;
        
        new com.google.android.material.dialog.MaterialAlertDialogBuilder(this)
                .setTitle("Transaction Timeout")
                .setMessage(message != null ? message : "This transaction is taking longer than expected. Would you like to keep waiting or return home?")
                .setPositiveButton("Keep Waiting", (dialog, which) -> {
                    // Do nothing, just dismiss. We already set hasShownTimeoutPrompt = true
                    // so it won't show again immediately.
                })
                .setNegativeButton("Return Home", (dialog, which) -> {
                    finish();
                })
                .setCancelable(false)
                .show();
    }

    private String formatType(String type) {
        if (type == null) return "Send";
        switch (type) {
            case TxForegroundService.ACTION_SEND:
                return "Send";
            case TxForegroundService.ACTION_TOKEN_SEND:
                return "Token Transfer";
            case TxForegroundService.ACTION_ENCRYPT:
                return "Encrypt Balance";
            case TxForegroundService.ACTION_DECRYPT:
                return "Decrypt Balance";
            case TxForegroundService.ACTION_STEALTH:
                return "Stealth Send";
            default:
                return "Transaction";
        }
    }

    private String resolveTokenSymbolForResult() {
        try {
            TxTaskStore.TaskItem task = TxTaskStore.getTaskById(getApplicationContext(), txId);
            if (task == null) return "";
            return extractTokenSymbol(task.message);
        } catch (Exception ignored) {
            return "";
        }
    }

    private String extractTokenSymbol(String message) {
        if (message == null) return "";
        String text = message.trim();
        if (text.isEmpty()) return "";

        if (text.startsWith("{") && text.endsWith("}")) {
            try {
                JSONObject obj = new JSONObject(text);
                String sym = obj.optString("token_symbol", "");
                if (sym.isEmpty()) sym = obj.optString("symbol", "");
                if (sym.isEmpty()) sym = obj.optString("ticker", "");
                if (sym.isEmpty()) sym = obj.optString("token", "");
                return sym == null ? "" : sym.trim();
            } catch (Exception ignored) {
            }
        }

        String lower = text.toLowerCase(Locale.US);
        String token = extractTokenAfterKey(text, lower, "token:");
        if (!token.isEmpty()) return token;
        token = extractTokenAfterKey(text, lower, "token_symbol:");
        if (!token.isEmpty()) return token;
        return extractTokenAfterKey(text, lower, "symbol:");
    }

    private String extractTokenAfterKey(String original, String lower, String key) {
        int idx = lower.indexOf(key);
        if (idx < 0) return "";
        String tail = original.substring(idx + key.length()).trim();
        if (tail.isEmpty()) return "";
        String[] parts = Pattern.compile("[^A-Za-z0-9_]+")
                .split(tail, 2);
        return parts.length > 0 ? parts[0].trim() : "";
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        mainHandler.removeCallbacks(pollRunnable);
        TxForegroundService.setCallback(null);
    }

    private void clearResultNotification() {
        int notifId = getIntent().getIntExtra(
                TxForegroundService.EXTRA_RESULT_NOTIFICATION_ID,
                TxForegroundService.resultNotificationIdForTask(txId)
        );
        android.app.NotificationManager notificationManager = getSystemService(android.app.NotificationManager.class);
        if (notificationManager != null) {
            notificationManager.cancel(notifId);
            if (txId != null && !txId.trim().isEmpty()) {
                notificationManager.cancel(TxForegroundService.resultNotificationIdForTask(txId));
            }
        }
    }
}
