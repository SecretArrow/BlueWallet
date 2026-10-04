package com.octopus.wallet;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;
import androidx.work.Worker;
import androidx.work.WorkerParameters;

import org.json.JSONObject;

import java.io.File;
import java.util.List;

/**
 * WorkManager worker that performs a periodic balance/incoming-tx scan.
 * This is a battery-friendly alternative to {@link AutoScanService};
 * use it when the foreground service approach is too aggressive.
 *
 * <p>All RPC calls are delegated to {@link WalletRepository}, which
 * in turn uses the singleton {@link OctraRpcClient}.</p>
 */
public class AutoScanWorker extends Worker {

    public static final String TAG_PERIODIC = "auto_scan_periodic";
    private static final String LOG_TAG     = "AutoScanWorker";
    private static final String CHANNEL_ID  = AutoScanService.CHANNEL_INCOMING_ID;
    private static final int    NOTIF_ID    = 5300;

    private static final String PREFS        = "auto_scan_worker_runtime";
    private static final String KEY_LAST_HASH_PREFIX = "worker_last_hash_";

    public AutoScanWorker(@NonNull Context context, @NonNull WorkerParameters params) {
        super(context, params);
    }

    private WalletRepository repo() {
        return new WalletRepository(getApplicationContext());
    }

    @NonNull
    @Override
    public Result doWork() {
        Context ctx = getApplicationContext();
        try {
            // Ensure native library is initialised
            WalletProfileStore.ensureDefault(ctx);
            String selectedId = WalletProfileStore.getSelectedWalletId(ctx);
            File walletDir = WalletProfileStore.getWalletDir(ctx, selectedId);
            OctraNative.getInstance().init(walletDir.getAbsolutePath());

            JSONObject info = new JSONObject(OctraNative.getInstance().getWalletInfo());
            if (info.has("error")) {
                Log.w(LOG_TAG, "Wallet info error: " + info.optString("error"));
                return Result.success(); // wallet locked — nothing we can do
            }

            String rpcUrl = info.optString("rpc_url", UrlSecurityValidator.DEFAULT_RPC);
            String address = info.getString("address");

            // Store/update wallet address mapping
            WalletAddressStore.putAddress(ctx, selectedId, address);

            // Check for new incoming transactions
            checkIncoming(ctx, rpcUrl, address);

            // Notify any live UI listener
            AutoScanService.ScanListener listener = AutoScanService.sScanListener;
            if (listener != null) {
                listener.onBalanceUpdated();
            }

            return Result.success();
        } catch (Exception e) {
            Log.w(LOG_TAG, "Worker scan failed: " + e.getMessage());
            return Result.success(); // don't retry on partial errors
        }
    }

    // ── Incoming-tx detection ──────────────────────────────────────────────

    private void checkIncoming(Context ctx, String rpcUrl, String address) {
        try {
            List<JSONObject> history = repo().fetchHistory(rpcUrl, address, 10, 0);
            if (history.isEmpty()) return;

            for (JSONObject tx : history) {
                if (tx == null) continue;

                String to   = firstNonEmpty(tx.optString("to", ""), tx.optString("recipient", ""));
                String from = firstNonEmpty(tx.optString("from", ""), tx.optString("sender", ""));
                String status = tx.optString("status", "");

                if (!address.equalsIgnoreCase(to.trim())) continue;
                if (from.trim().isEmpty() || from.equalsIgnoreCase(address)) continue;
                String ns = status.toLowerCase();
                if (ns.contains("reject") || ns.contains("fail")) continue;

                String hash = firstNonEmpty(tx.optString("hash", ""), tx.optString("tx_hash", "")).trim();
                if (hash.isEmpty()) continue;

                String key     = KEY_LAST_HASH_PREFIX + address;
                String lastHash = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                        .getString(key, "");
                if (hash.equals(lastHash)) break; // already notified

                // Found a new incoming tx — notify
                String amountRaw = firstNonEmpty(tx.optString("amount_raw", ""), tx.optString("amount", "0"));
                String symbol    = firstNonEmpty(tx.optString("token_symbol", ""), tx.optString("symbol", "OCT"));
                if (symbol.isEmpty()) symbol = "OCT";

                postIncomingNotification(ctx, from, amountRaw, symbol, address, hash);
                ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                        .edit().putString(key, hash).apply();
                break;
            }
        } catch (Exception e) {
            Log.w(LOG_TAG, "Incoming check failed: " + e.getMessage());
        }
    }

    private void postIncomingNotification(Context ctx, String from, String amountRaw,
                                           String symbol, String toAddress, String hash) {
        ensureChannel(ctx);
        if (!hasNotifPermission(ctx)) return;

        String title = "OCT".equalsIgnoreCase(symbol) ? "Incoming OCT Received" : "Incoming " + symbol + " Received";
        String amount = formatAmount(amountRaw) + " " + symbol;
        String text   = "From: " + compact(from) + " · Amount: " + amount;

        Intent intent = new Intent(ctx, MainActivity.class);
        intent.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent pi = PendingIntent.getActivity(ctx, hash.hashCode() & 0xffff,
                intent, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        Notification notif = new NotificationCompat.Builder(ctx, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(new NotificationCompat.BigTextStyle().bigText(text))
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setContentIntent(pi)
                .build();

        NotificationManagerCompat.from(ctx).notify(NOTIF_ID + (hash.hashCode() & 0xffff), notif);
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    private static String firstNonEmpty(String... vals) {
        for (String v : vals) if (v != null && !v.trim().isEmpty()) return v;
        return "";
    }

    private static String compact(String addr) {
        if (addr == null || addr.length() <= 16) return addr == null ? "" : addr;
        return addr.substring(0, 8) + "…" + addr.substring(addr.length() - 8);
    }

    private static String formatAmount(String raw) {
        try {
            long r = Long.parseLong(raw.trim());
            java.math.BigDecimal v = java.math.BigDecimal.valueOf(r, 6).stripTrailingZeros();
            if (v.scale() < 0) v = v.setScale(0);
            return v.toPlainString();
        } catch (Exception e) {
            return raw == null ? "0" : raw;
        }
    }

    private static void ensureChannel(Context ctx) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationManager nm = ctx.getSystemService(NotificationManager.class);
            if (nm == null) return;
            if (nm.getNotificationChannel(CHANNEL_ID) != null) return;
            NotificationChannel ch = new NotificationChannel(
                    CHANNEL_ID, "Incoming Transactions", NotificationManager.IMPORTANCE_HIGH);
            ch.setDescription("Alerts for new incoming OCT or token transfers");
            ch.enableVibration(true);
            nm.createNotificationChannel(ch);
        }
    }

    private static boolean hasNotifPermission(Context ctx) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return ctx.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                    == PackageManager.PERMISSION_GRANTED;
        }
        return true;
    }
}
