package com.octopus.wallet;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;

import androidx.core.app.NotificationCompat;
import androidx.core.content.ContextCompat;

import org.json.JSONArray;
import org.json.JSONObject;

public class StealthClaimService extends Service {
    private static final String CHANNEL_ID = "stealth_claim";
    private static final int ONGOING_NOTIFICATION_ID = 6101;
    private static final int RESULT_NOTIFICATION_ID = 6102;
    private static final String EXTRA_OUTPUTS_JSON = "outputs_json";

    public static void startClaiming(android.content.Context context, JSONArray selectedOutputs) {
        Intent intent = new Intent(context, StealthClaimService.class);
        intent.putExtra(EXTRA_OUTPUTS_JSON, selectedOutputs == null ? "[]" : selectedOutputs.toString());
        ContextCompat.startForegroundService(context.getApplicationContext(), intent);
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String raw = intent == null ? "[]" : intent.getStringExtra(EXTRA_OUTPUTS_JSON);
        JSONArray outputs;
        try {
            outputs = new JSONArray(raw == null ? "[]" : raw);
        } catch (Exception e) {
            outputs = new JSONArray();
        }

        startForegroundCompat(buildNotification("Preparing claim queue...", true));

        final JSONArray finalOutputs = outputs;
        new Thread(() -> processClaims(finalOutputs)).start();
        return START_NOT_STICKY;
    }

    private void processClaims(JSONArray outputs) {
        int total = outputs == null ? 0 : outputs.length();
        int queued = 0;
        int skipped = 0;
        long totalAmountRaw = 0L;

        for (int i = 0; i < total; i++) {
            try {
                JSONObject item = outputs.optJSONObject(i);
                if (item == null) {
                    skipped++;
                    continue;
                }
                String outputId = item.optString("output_id", "").trim();
                long amountRaw = parseRaw(item.optString("amount_raw", "0"));
                if (amountRaw <= 0L) {
                    skipped++;
                    continue;
                }

                String txId = "tx_claim_" + System.currentTimeMillis() + "_" + i;
                TxForegroundService.startTx(
                        getApplicationContext(),
                        TxForegroundService.ACTION_DECRYPT,
                        txId,
                        null,
                        amountRaw,
                        outputId.isEmpty() ? "stealth-claim" : ("stealth-claim:" + outputId)
                );
                queued++;
                totalAmountRaw += amountRaw;
                updateProgress(queued, total);
                try {
                    Thread.sleep(250L);
                } catch (InterruptedException ignored) {
                }
            } catch (Exception ignored) {
                skipped++;
            }
        }

        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm != null) {
            nm.cancel(ONGOING_NOTIFICATION_ID);
            String amountDisplay = formatOctAmount(totalAmountRaw);
            String summary;
            if (queued == 0) {
                summary = "No stealth outputs to claim"
                        + (skipped > 0 ? " (" + skipped + " skipped)" : "") + ".";
            } else {
                summary = "Claiming " + queued + " stealth output" + (queued > 1 ? "s" : "")
                        + " worth " + amountDisplay + " OCT."
                        + (skipped > 0 ? " (" + skipped + " skipped)" : "")
                        + "\nOpen Transactions Manager to track progress.";
            }
            nm.notify(RESULT_NOTIFICATION_ID, buildResultNotification(summary));
        }
        stopForeground(STOP_FOREGROUND_REMOVE);
        stopSelf();
    }

    /** Formats a raw micro-OCT amount (6 decimal places) as a human-readable string. */
    private static String formatOctAmount(long rawMicrocoins) {
        if (rawMicrocoins <= 0L) return "0";
        java.math.BigDecimal v = java.math.BigDecimal.valueOf(rawMicrocoins, 6)
                .stripTrailingZeros();
        if (v.scale() < 0) v = v.setScale(0);
        return v.toPlainString();
    }

    private void updateProgress(int queued, int total) {
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm == null) return;
        String text = "Queueing claim tasks... (" + queued + "/" + total + ")";
        nm.notify(ONGOING_NOTIFICATION_ID, buildNotification(text, true));
    }

    private Notification buildNotification(String text, boolean ongoing) {
        Intent intent = new Intent(this, TransactionsManagerActivity.class);
        intent.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent pi = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        return new NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle("Stealth Claim")
                .setContentText(text)
                .setStyle(new NotificationCompat.BigTextStyle().bigText(text))
                .setOngoing(ongoing)
                .setAutoCancel(!ongoing)
                .setContentIntent(pi)
                .build();
    }

    /**
     * High-priority result notification shown when queueing is complete.
     * Tapping it opens the Transactions Manager to track claim progress.
     */
    private Notification buildResultNotification(String text) {
        Intent intent = new Intent(this, TransactionsManagerActivity.class);
        intent.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent pi = PendingIntent.getActivity(
                this,
                1,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        return new NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stealth)
                .setContentTitle("Stealth Claim Queued")
                .setContentText(text)
                .setStyle(new NotificationCompat.BigTextStyle().bigText(text))
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setContentIntent(pi)
                .build();
    }

    private void startForegroundCompat(Notification notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(ONGOING_NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC);
        } else {
            startForeground(ONGOING_NOTIFICATION_ID, notification);
        }
    }

    private long parseRaw(String value) {
        try {
            return Math.max(0L, Long.parseLong(value == null ? "0" : value.trim()));
        } catch (Exception e) {
            return 0L;
        }
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID,
                    "Stealth Claim",
                    NotificationManager.IMPORTANCE_LOW
            );
            channel.setDescription("Stealth claim background tasks");
            NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm != null) {
                nm.createNotificationChannel(channel);
            }
        }
    }
}
