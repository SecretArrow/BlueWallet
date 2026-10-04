package com.octopus.wallet;

import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.widget.TextView;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

public class StealthTaskDetailActivity extends BaseTxActivity {
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable refreshRunnable = this::refreshDetail;
    private String taskId;

    private TextView idText, toText, amountText, statusText, stepText,
            messageText, hashText, createdText, updatedText;
    private TextView dataSentText, dataReceivedText, dataTotalText;
    private DataUsageTracker dataUsageTracker;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_stealth_task_detail);
        setupToolbar(R.id.stealth_detail_toolbar, "Stealth Task");

        taskId = getIntent().getStringExtra("task_id");
        if (taskId != null && !taskId.trim().isEmpty()) {
            TxTaskStore.markTaskOpened(getApplicationContext(), taskId);
        }
        clearResultNotification();
        TxForegroundService.clearTaskNotifications(this, taskId);

        idText = findViewById(R.id.detail_task_id);
        toText = findViewById(R.id.detail_task_to);
        amountText = findViewById(R.id.detail_task_amount);
        statusText = findViewById(R.id.detail_task_status);
        stepText = findViewById(R.id.detail_task_step);
        messageText = findViewById(R.id.detail_task_message);
        hashText = findViewById(R.id.detail_task_hash);
        createdText = findViewById(R.id.detail_task_created);
        updatedText = findViewById(R.id.detail_task_updated);
        dataSentText = findViewById(R.id.detail_data_sent);
        dataReceivedText = findViewById(R.id.detail_data_received);
        dataTotalText = findViewById(R.id.detail_data_total);

        dataUsageTracker = new DataUsageTracker(this);

        refreshDetail();
    }

    private void refreshDetail() {
        if (taskId == null || taskId.isEmpty()) return;
        try {
            StealthTaskManager.TaskItem item = StealthTaskManager.getTaskById(getApplicationContext(), taskId);

            // Fallback to TxTaskStore if not found in StealthTaskManager
            if (item == null) {
                TxTaskStore.TaskItem txItem = TxTaskStore.getTaskById(getApplicationContext(), taskId);
                if (txItem != null) {
                    // Translate TxTaskStore fields to display
                    idText.setText(txItem.id);
                    toText.setText(txItem.to == null || txItem.to.isEmpty() ? "-" : txItem.to);
                    amountText.setText(formatRaw(txItem.amountRaw) + " OCT");
                    statusText.setText(txItem.status == null ? "Unknown" : txItem.status);
                    stepText.setText(txItem.step == null ? "-" : txItem.step);
                    messageText.setText(txItem.progressMessage == null || txItem.progressMessage.isEmpty() ? "-" : txItem.progressMessage);
                    String hash = txItem.txHash == null || txItem.txHash.isEmpty() ? "-" : txItem.txHash;
                    hashText.setText(hash.equals("-") ? "-" : "Hash: " + hash);
                    createdText.setText(formatTime(txItem.createdAt));
                    updatedText.setText(formatTime(txItem.updatedAt));
                    return;
                }
                idText.setText(taskId);
                statusText.setText("Not Found");
                return;
            }

            idText.setText(item.id);
            toText.setText(item.to == null || item.to.isEmpty() ? "-" : item.to);
            amountText.setText(formatRaw(item.amountRaw) + " OCT");
            String normalized = StealthTaskManager.normalizeStatus(item.status);
            String lifeCycle = StealthTaskManager.isFinishedStatus(normalized) ? "Finished" : "Running";
            String result;
            if (StealthTaskManager.STATUS_SUCCESS.equals(normalized)) {
                result = "Success";
            } else if (StealthTaskManager.STATUS_FAILED.equals(normalized)) {
                result = "Failed";
            } else {
                result = "In Progress";
            }
            statusText.setText(lifeCycle + " (" + result + ")");
            stepText.setText(item.step == null ? "-" : item.step);
            messageText.setText(item.message == null || item.message.isEmpty() ? "-" : item.message);
            String hash = item.txHash == null || item.txHash.isEmpty() ? "-" : item.txHash;
            hashText.setText(hash.equals("-") ? "-" : "Hash: " + hash);
            createdText.setText(formatTime(item.createdAt));
            updatedText.setText(formatTime(item.updatedAt));

            boolean active = StealthTaskManager.isActiveStatus(normalized);
            if (!active) {
                TxForegroundService.clearTaskNotifications(this, taskId);
            }

            // Update data usage display
            updateDataUsageDisplay();

            handler.removeCallbacks(refreshRunnable);
            if (active) {
                handler.postDelayed(refreshRunnable, 10_000L);
            }
        } catch (Exception ignored) {
        }
    }

    private void updateDataUsageDisplay() {
        try {
            if (dataUsageTracker != null) {
                DataUsageTracker.DataUsage sessionUsage = dataUsageTracker.getSessionUsage();
                if (dataSentText != null) {
                    dataSentText.setText(sessionUsage.getFormattedTx());
                }
                if (dataReceivedText != null) {
                    dataReceivedText.setText(sessionUsage.getFormattedRx());
                }
                if (dataTotalText != null) {
                    dataTotalText.setText(sessionUsage.getFormattedTotal());
                }
            }
        } catch (Exception ignored) {
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        refreshDetail();
    }

    @Override
    protected void onPause() {
        super.onPause();
        handler.removeCallbacks(refreshRunnable);
    }

    @Override
    protected void onDestroy() {
        handler.removeCallbacks(refreshRunnable);
        super.onDestroy();
    }

    private String formatRaw(String raw) {
        try {
            long v = Long.parseLong(raw == null ? "0" : raw);
            BigDecimal bd = BigDecimal.valueOf(v, 6).setScale(6, RoundingMode.DOWN).stripTrailingZeros();
            if (bd.scale() < 0) bd = bd.setScale(0);
            return bd.toPlainString();
        } catch (Exception e) {
            return "0";
        }
    }

    private String formatTime(long ts) {
        if (ts <= 0L) return "-";
        return new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(new Date(ts));
    }

    private void clearResultNotification() {
        int notifId = getIntent().getIntExtra(
                TxForegroundService.EXTRA_RESULT_NOTIFICATION_ID,
                TxForegroundService.resultNotificationIdForTask(taskId)
        );
        android.app.NotificationManager notificationManager = getSystemService(android.app.NotificationManager.class);
        if (notificationManager != null) {
            notificationManager.cancel(notifId);
            if (taskId != null && !taskId.trim().isEmpty()) {
                notificationManager.cancel(TxForegroundService.resultNotificationIdForTask(taskId));
            }
        }
    }
}
