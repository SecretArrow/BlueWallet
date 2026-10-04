package com.octopus.wallet;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.util.Log;

import androidx.core.app.NotificationCompat;
import androidx.core.content.ContextCompat;
import androidx.core.app.NotificationManagerCompat;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Foreground service that periodically scans for balance updates.
 * All RPC calls are delegated to {@link WalletRepository} via
 * {@link OctraRpcClient}, so there is no local OkHttp usage.
 */
public class AutoScanService extends Service {

    private static final String TAG = "AutoScanService";
    public static final String CHANNEL_ID = "auto_scan";
    public static final String CHANNEL_INCOMING_ID = "incoming_alerts";
    private static final int NOTIFICATION_ID = 5001;
    private static final int INCOMING_BASE_NOTIFICATION_ID = 5200;
    private static final String FOREGROUND_TEXT = "Your gateway to encrypted power for blockchain, AI, and next-gen apps";
    private static final String PREFS = "auto_scan_runtime";
    private static final String KEY_LAST_INCOMING_HASH_PREFIX = "last_incoming_hash_";

    private final Handler handler = new Handler(Looper.getMainLooper());
    private Runnable scanRunnable;
    private boolean running = false;

    private WalletRepository repo() {
        return new WalletRepository(getApplicationContext());
    }

    // Listener for balance updates (set by MainActivity)
    public interface ScanListener {
        void onBalanceUpdated();
    }

    static volatile ScanListener sScanListener;

    public static void setScanListener(ScanListener listener) {
        sScanListener = listener;
    }

    public static void startScanning(Context context) {
        int minutes = AutoScanActivity.getScanIntervalMinutes(context);
        if (minutes <= 0) {
            stopScanning(context);
            return;
        }
        Intent intent = new Intent(context, AutoScanService.class);
        intent.putExtra("interval_minutes", minutes);
        ContextCompat.startForegroundService(context, intent);
    }

    public static void stopScanning(Context context) {
        try {
            context.stopService(new Intent(context, AutoScanService.class));
        } catch (Exception ignored) {
        }
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
        int intervalMinutes = 0;
        if (intent != null) {
            intervalMinutes = intent.getIntExtra("interval_minutes", 0);
        }
        if (intervalMinutes <= 0) {
            intervalMinutes = AutoScanActivity.getScanIntervalMinutes(this);
        }
        if (intervalMinutes <= 0) {
            stopSelf();
            return START_NOT_STICKY;
        }

        Notification notification = buildNotification(FOREGROUND_TEXT);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC);
        } else {
            startForeground(NOTIFICATION_ID, notification);
        }

        running = true;
        final long intervalMs = intervalMinutes * 60L * 1000L;

        // Cancel any existing scan runnable
        if (scanRunnable != null) {
            handler.removeCallbacks(scanRunnable);
        }

        scanRunnable = new Runnable() {
            @Override
            public void run() {
                if (!running) return;
                doScan();
                handler.postDelayed(this, intervalMs);
            }
        };

        // Start first scan after the interval
        handler.postDelayed(scanRunnable, intervalMs);

        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        running = false;
        if (scanRunnable != null) {
            handler.removeCallbacks(scanRunnable);
            scanRunnable = null;
        }
        super.onDestroy();
    }

    private void doScan() {
        new Thread(() -> {
            try {
                JSONObject info = new JSONObject(OctraNative.getInstance().getWalletInfo());
                if (info.has("error")) return;

                String rpcUrl = info.optString("rpc_url", UrlSecurityValidator.DEFAULT_RPC);
                String address = info.getString("address");
                String selectedWalletId = WalletProfileStore.getSelectedWalletId(getApplicationContext());
                WalletAddressStore.putAddress(getApplicationContext(), selectedWalletId, address);

                // Balance check via WalletRepository
                WalletRepository.Result<WalletRepository.BalanceSummary> balResult =
                        repo().fetchBalance(rpcUrl, address);
                if (balResult.isSuccess()) {
                    Log.d(TAG, "Auto scan completed successfully");
                    maybeNotifyIncomingForAllWallets(rpcUrl, address);
                    // Notify listener to refresh UI
                    ScanListener listener = sScanListener;
                    if (listener != null) {
                        handler.post(listener::onBalanceUpdated);
                    }
                }
            } catch (Exception e) {
                Log.w(TAG, "Auto scan failed: " + e.getMessage());
            }
        }).start();
    }

    private void maybeNotifyIncomingForAllWallets(String rpcUrl, String activeAddress) {
        try {
            Map<String, String> allWalletAddresses = new HashMap<>(WalletAddressStore.getAllAddresses(getApplicationContext()));
            if (activeAddress != null && !activeAddress.trim().isEmpty()) {
                String selected = WalletProfileStore.getSelectedWalletId(getApplicationContext());
                allWalletAddresses.put(selected, activeAddress.trim());
            }

            Set<String> uniqueAddresses = new HashSet<>();
            for (String value : allWalletAddresses.values()) {
                if (value != null && !value.trim().isEmpty()) {
                    uniqueAddresses.add(value.trim());
                }
            }

            for (String address : uniqueAddresses) {
                maybeNotifyIncoming(rpcUrl, address);
            }
        } catch (Exception e) {
            Log.w(TAG, "Incoming all-wallet scan failed: " + e.getMessage());
        }
    }

    private void maybeNotifyIncoming(String rpcUrl, String address) {
        try {
            List<JSONObject> history = repo().fetchHistory(rpcUrl, address, 20, 0);
            if (history.isEmpty()) return;

            JSONObject latestIncoming = null;
            for (JSONObject tx : history) {
                if (tx == null) continue;

                String to = firstNonEmpty(
                    tx.optString("to", ""),
                    tx.optString("recipient", ""),
                    tx.optString("to_", ""),
                    tx.optJSONObject("transaction") == null ? "" : tx.optJSONObject("transaction").optString("to", ""),
                    tx.optJSONObject("tx") == null ? "" : tx.optJSONObject("tx").optString("to", "")
                );
                String from = firstNonEmpty(
                    tx.optString("from", ""),
                    tx.optString("sender", ""),
                    tx.optString("from_", ""),
                    tx.optJSONObject("transaction") == null ? "" : tx.optJSONObject("transaction").optString("from", ""),
                    tx.optJSONObject("tx") == null ? "" : tx.optJSONObject("tx").optString("from", "")
                );
                String status = firstNonEmpty(
                    tx.optString("status", ""),
                    tx.optString("tx_status", ""),
                    tx.optString("state", ""),
                    tx.optJSONObject("transaction") == null ? "" : tx.optJSONObject("transaction").optString("status", ""),
                    tx.optJSONObject("tx") == null ? "" : tx.optJSONObject("tx").optString("status", "")
                );

                if (!address.equalsIgnoreCase(to.trim())) {
                    continue;
                }
                String normalized = status == null ? "" : status.toLowerCase();
                if (normalized.contains("reject") || normalized.contains("fail") || normalized.contains("error")) {
                    continue;
                }
                if (from.trim().isEmpty() || from.equalsIgnoreCase(address)) {
                    continue;
                }
                latestIncoming = tx;
                break;
            }

            if (latestIncoming == null) {
                return;
            }

            String hash = firstNonEmpty(latestIncoming.optString("hash", ""), latestIncoming.optString("tx_hash", "")).trim();
            if (hash.isEmpty()) {
                return;
            }

            String key = KEY_LAST_INCOMING_HASH_PREFIX + address;
            String lastHash = getSharedPreferences(PREFS, MODE_PRIVATE).getString(key, "");
            if (hash.equals(lastHash)) {
                return;
            }

                JSONObject txNested = latestIncoming.optJSONObject("transaction");
                JSONObject txAlt = latestIncoming.optJSONObject("tx");

                String from = firstNonEmpty(
                    latestIncoming.optString("from", ""),
                    latestIncoming.optString("sender", ""),
                    latestIncoming.optString("from_", ""),
                    txNested == null ? "" : txNested.optString("from", ""),
                    txAlt == null ? "" : txAlt.optString("from", "")
                );
                String amountRaw = firstNonEmpty(
                    latestIncoming.optString("amount_raw", ""),
                    latestIncoming.optString("value_raw", ""),
                    latestIncoming.optString("token_amount_raw", ""),
                    latestIncoming.optString("amount", ""),
                    latestIncoming.optString("value", ""),
                    latestIncoming.optString("token_amount", ""),
                    txNested == null ? "" : firstNonEmpty(
                        txNested.optString("amount_raw", ""),
                        txNested.optString("value_raw", ""),
                        txNested.optString("token_amount_raw", ""),
                        txNested.optString("amount", ""),
                        txNested.optString("value", ""),
                        txNested.optString("token_amount", "")
                    ),
                    txAlt == null ? "" : firstNonEmpty(
                        txAlt.optString("amount_raw", ""),
                        txAlt.optString("value_raw", ""),
                        txAlt.optString("token_amount_raw", ""),
                        txAlt.optString("amount", ""),
                        txAlt.optString("value", ""),
                        txAlt.optString("token_amount", "")
                    )
                );
                String symbol = firstNonEmpty(
                    latestIncoming.optString("token_symbol", ""),
                    latestIncoming.optString("symbol", ""),
                    latestIncoming.optString("ticker", ""),
                    latestIncoming.optString("asset_symbol", ""),
                    latestIncoming.optString("token", ""),
                    txNested == null ? "" : firstNonEmpty(
                        txNested.optString("token_symbol", ""),
                        txNested.optString("symbol", ""),
                        txNested.optString("ticker", ""),
                        txNested.optString("asset_symbol", ""),
                        txNested.optString("token", "")
                    ),
                    txAlt == null ? "" : firstNonEmpty(
                        txAlt.optString("token_symbol", ""),
                        txAlt.optString("symbol", ""),
                        txAlt.optString("ticker", ""),
                        txAlt.optString("asset_symbol", ""),
                        txAlt.optString("token", "")
                    )
                ).trim();
                if (symbol.isEmpty()) {
                symbol = "OCT";
                }
                String when = firstNonEmpty(
                    latestIncoming.optString("timestamp", ""),
                    latestIncoming.optString("time", ""),
                    latestIncoming.optString("created_at", ""),
                    txNested == null ? "" : firstNonEmpty(
                        txNested.optString("timestamp", ""),
                        txNested.optString("time", ""),
                        txNested.optString("created_at", "")
                    ),
                    txAlt == null ? "" : firstNonEmpty(
                        txAlt.optString("timestamp", ""),
                        txAlt.optString("time", ""),
                        txAlt.optString("created_at", "")
                    )
                );

                String title = "OCT".equalsIgnoreCase(symbol) ? "Incoming OCT Received" : "Incoming Token Received";
                String amountText = formatIncomingAmount(amountRaw, symbol);
                String text = "From: " + compactAddress(from) + " • Amount: " + amountText + " • Time: " + formatTime(when);

            Intent notifIntent = new Intent(this, MainActivity.class);
            notifIntent.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            PendingIntent pi = PendingIntent.getActivity(
                    this,
                    INCOMING_BASE_NOTIFICATION_ID + (hash.hashCode() & 0x7fffffff) % 100000,
                    notifIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
            );

            Notification notification = new NotificationCompat.Builder(this, CHANNEL_INCOMING_ID)
                    .setSmallIcon(R.drawable.ic_notification)
                    .setContentTitle(title)
                    .setContentText(text)
                    .setStyle(new NotificationCompat.BigTextStyle().bigText(text))
                    .setAutoCancel(true)
                    .setPriority(NotificationCompat.PRIORITY_HIGH)
                    .setContentIntent(pi)
                    .build();

            if (hasNotificationPermission()) {
                NotificationManagerCompat.from(this)
                        .notify(INCOMING_BASE_NOTIFICATION_ID + (hash.hashCode() & 0x7fffffff) % 100000, notification);
            }

            getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString(key, hash).apply();
        } catch (Exception e) {
            Log.w(TAG, "Incoming notify check failed: " + e.getMessage());
        }
    }

    private String firstNonEmpty(String... values) {
        if (values == null) return "";
        for (String value : values) {
            if (value != null && !value.trim().isEmpty()) {
                return value;
            }
        }
        return "";
    }

    private String compactAddress(String value) {
        if (value == null || value.trim().isEmpty()) return "Unknown";
        String v = value.trim();
        if (v.length() <= 20) return v;
        return v.substring(0, 8) + "..." + v.substring(v.length() - 8);
    }

    private String formatAmount(String rawAmount) {
        try {
            long raw = Long.parseLong(rawAmount == null || rawAmount.trim().isEmpty() ? "0" : rawAmount.trim());
            java.math.BigDecimal value = java.math.BigDecimal.valueOf(raw, 6)
                    .setScale(6, java.math.RoundingMode.DOWN)
                    .stripTrailingZeros();
            if (value.scale() < 0) value = value.setScale(0);
            return value.toPlainString();
        } catch (Exception ignored) {
            return "0";
        }
    }

    private String formatIncomingAmount(String amountRaw, String symbol) {
        String normalizedSymbol = (symbol == null || symbol.trim().isEmpty()) ? "OCT" : symbol.trim();
        if (amountRaw == null || amountRaw.trim().isEmpty()) {
            return "0 " + normalizedSymbol;
        }
        String value = amountRaw.trim();
        if (value.contains(".")) {
            return value + " " + normalizedSymbol;
        }
        return formatAmount(value) + " " + normalizedSymbol;
    }

    private String formatTime(String rawTs) {
        try {
            if (rawTs == null || rawTs.trim().isEmpty()) return "-";
            double parsed = Double.parseDouble(rawTs.trim());
            long millis = parsed > 1000000000000d ? (long) parsed : (long) (parsed * 1000d);
            java.text.SimpleDateFormat sdf = new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm", java.util.Locale.getDefault());
            return sdf.format(new java.util.Date(millis));
        } catch (Exception ignored) {
            return rawTs == null || rawTs.trim().isEmpty() ? "-" : rawTs;
        }
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm == null) return;

            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID, "Auto Scan",
                    NotificationManager.IMPORTANCE_LOW);
            channel.setDescription("Background balance scanning");
            nm.createNotificationChannel(channel);

            NotificationChannel incomingChannel = new NotificationChannel(
                    CHANNEL_INCOMING_ID, "Incoming Transactions",
                    NotificationManager.IMPORTANCE_HIGH);
            incomingChannel.setDescription("Notifications for incoming OCT and token transfers");
            incomingChannel.enableVibration(true);
            nm.createNotificationChannel(incomingChannel);
        }
    }

    private boolean hasNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                    == android.content.pm.PackageManager.PERMISSION_GRANTED;
        }
        return true;
    }

    private Notification buildNotification(String text) {
        Intent notifIntent = new Intent(this, MainActivity.class);
        notifIntent.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent pi = PendingIntent.getActivity(this, 0, notifIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        return new NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle("Octra Wallet")
                .setContentText(text)
            .setStyle(new NotificationCompat.BigTextStyle().bigText(text))
                .setOngoing(true)
                .setContentIntent(pi)
                .build();
    }
}
