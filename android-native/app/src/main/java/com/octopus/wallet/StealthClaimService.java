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

import android.util.Log;

import java.util.concurrent.atomic.AtomicBoolean;

import org.json.JSONArray;
import org.json.JSONObject;

public class StealthClaimService extends Service {
    private static final String TAG = "StealthClaimService";
    private static final String CHANNEL_ID = "stealth_claim";
    private static final String CHANNEL_RESULT_ID = "stealth_claim_result";
    private static final int ONGOING_NOTIFICATION_ID = 6101;
    private static final int RESULT_NOTIFICATION_ID = 6102;
    private static final String EXTRA_OUTPUTS_JSON = "outputs_json";

    /** Single-instance guard: only one queueing pass may run at a time. */
    private final AtomicBoolean busy = new AtomicBoolean(false);
    private volatile Thread worker;
    private volatile boolean cancelled;

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
        if (!busy.compareAndSet(false, true)) {
            Log.w(TAG, "Claim queue already running, ignoring duplicate start");
            return START_NOT_STICKY;
        }
        cancelled = false;

        String raw = intent == null ? "[]" : intent.getStringExtra(EXTRA_OUTPUTS_JSON);
        JSONArray outputs;
        try {
            outputs = new JSONArray(raw == null ? "[]" : raw);
        } catch (Exception e) {
            Log.w(TAG, "Invalid outputs payload: " + e.getMessage());
            outputs = new JSONArray();
        }

        startForegroundCompat(buildNotification("Preparing claim queue...", true));

        final JSONArray finalOutputs = outputs;
        worker = new Thread(() -> {
            try {
                processClaims(finalOutputs);
            } finally {
                busy.set(false);
                worker = null;
                stopForeground(STOP_FOREGROUND_REMOVE);
                // Plain stopSelf(): rejected duplicate starts carry no work, so no
                // startId bookkeeping is needed (a duplicate startId would otherwise
                // make stopSelf(startId) a no-op and leak the foreground service).
                stopSelf();
            }
        });
        worker.setName("stealth-claim-worker");
        worker.start();
        return START_NOT_STICKY;
    }

    @Override
    public void onDestroy() {
        cancelled = true;
        Thread t = worker;
        if (t != null) t.interrupt();
        super.onDestroy();
    }

    private void processClaims(JSONArray outputs) {
        int total = outputs == null ? 0 : outputs.length();
        int queued = 0;
        int skipped = 0;
        long totalAmountRaw = 0L;

        for (int i = 0; i < total; i++) {
            if (cancelled || Thread.currentThread().isInterrupted()) {
                Log.d(TAG, "Claim queue cancelled, stopping");
                break;
            }
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

                String txId = "tx_claim_" + System.currentTimeMillis() + "_" + System.nanoTime() + "_" + i;
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
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    Log.d(TAG, "Claim queue pacing interrupted");
                    break;
                }
            } catch (Exception e) {
                Log.w(TAG, "Skipping claim item: " + e.getMessage());
                skipped++;
            }
        }

        if (hasNotificationPermission()) {
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
        } else {
            NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm != null) {
                nm.cancel(ONGOING_NOTIFICATION_ID);
            }
            Log.d(TAG, "Claim queue finished (queued=" + queued + ", skipped=" + skipped
                    + ") but POST_NOTIFICATIONS not granted; result notification skipped");
        }
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
        if (!hasNotificationPermission()) return;
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

        return new NotificationCompat.Builder(this, CHANNEL_RESULT_ID)
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

    private boolean hasNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                    == android.content.pm.PackageManager.PERMISSION_GRANTED;
        }
        return true;
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID,
                    "Stealth Claim",
                    NotificationManager.IMPORTANCE_LOW
            );
            channel.setDescription("Stealth claim background tasks");
            NotificationChannel resultChannel = new NotificationChannel(
                    CHANNEL_RESULT_ID,
                    "Stealth Claim Results",
                    NotificationManager.IMPORTANCE_HIGH
            );
            resultChannel.setDescription("Stealth claim queue results");
            resultChannel.enableVibration(true);
            NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm != null) {
                nm.createNotificationChannel(channel);
                nm.createNotificationChannel(resultChannel);
            }
        }
    }
}
