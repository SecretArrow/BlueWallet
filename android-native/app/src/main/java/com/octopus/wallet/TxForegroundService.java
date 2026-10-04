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
import android.os.IBinder;
import android.util.Base64;

import androidx.core.app.NotificationCompat;
import androidx.core.content.ContextCompat;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.security.SecureRandom;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

public class TxForegroundService extends Service {

    public static final String CHANNEL_ID = "tx_processing";
    public static final String CHANNEL_ALERT_ID = "tx_alerts";
    public static final String EXTRA_RESULT_NOTIFICATION_ID = "result_notification_id";
    public static final String ACTION_SEND = "send";
    public static final String ACTION_ENCRYPT = "encrypt";
    public static final String ACTION_DECRYPT = "decrypt";
    public static final String ACTION_STEALTH = "stealth";
    public static final String ACTION_TOKEN_SEND = "token_send";

    private static final String EXTRA_RECOVER_PENDING = "recover_pending";

    private static final int ONGOING_NOTIFICATION_ID = 3001;
    private static final int MAX_CONFIRM_POLLS = 720; // 1 hour maximum background polling
    private static final long CONFIRM_POLL_DELAY_MS = 5000L;
    private static final long STEALTH_HEARTBEAT_MS = 10_000L;
    private static final long NATIVE_CALL_TIMEOUT_MS = 600_000L; // 10 minutes timeout for native calls

    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final AtomicInteger activeJobs = new AtomicInteger(0);
    private final Set<String> runningTaskIds = new HashSet<>();

    /** Single-call repository accessor for this service's background operations. */
    private WalletRepository repo() {
        return new WalletRepository(getApplicationContext());
    }

    public interface TxCallback {
        void onTxProgress(String txId, String message);
        void onTxSuccess(String txId, String message, String txHash);
        void onTxFailed(String txId, String message);
        void onTxTimeout(String txId, String message);
    }

    static volatile TxCallback sCallback;

    public static void setCallback(TxCallback cb) {
        sCallback = cb;
    }

    public static int resultNotificationIdForTask(String txId) {
        int base = 4000;
        if (txId == null || txId.trim().isEmpty()) {
            return base;
        }
        int positiveHash = txId.hashCode() & 0x7fffffff;
        return base + (positiveHash % 100000);
    }

    public static void clearTaskNotifications(Context context, String txId) {
        if (context == null) return;
        Context appCtx = context.getApplicationContext();
        NotificationManager nm = appCtx.getSystemService(NotificationManager.class);
        if (nm == null) return;

        if (txId != null && !txId.trim().isEmpty()) {
            nm.cancel(resultNotificationIdForTask(txId));
        }
        if (!TxTaskStore.hasRecoverableTasks(appCtx)) {
            nm.cancel(ONGOING_NOTIFICATION_ID);
        }
    }

    public static void startTx(Context context, String txType, String txId,
                               String to, long amountRaw, String message) {
        String walletId = WalletProfileStore.getSelectedWalletId(context.getApplicationContext());
        TxTaskStore.clearTaskOpened(context.getApplicationContext(), txId);
        TxTaskStore.enqueue(context.getApplicationContext(), txId, txType, walletId, to, amountRaw, message);

        Intent intent = new Intent(context, TxForegroundService.class);
        intent.putExtra("tx_id", txId);
        ContextCompat.startForegroundService(context, intent);
    }

    public static void startStealth(Context context, String stealthTaskId,
                                    String to, long amountRaw, String message) {
        String walletId = WalletProfileStore.getSelectedWalletId(context.getApplicationContext());
        TxTaskStore.clearTaskOpened(context.getApplicationContext(), stealthTaskId);
        TxTaskStore.enqueue(context.getApplicationContext(), stealthTaskId,
                ACTION_STEALTH, walletId, to, amountRaw, message);

        Intent intent = new Intent(context, TxForegroundService.class);
        intent.putExtra("tx_id", stealthTaskId);
        ContextCompat.startForegroundService(context, intent);
    }

    public static void startRecovery(Context context) {
        Intent intent = new Intent(context, TxForegroundService.class);
        intent.putExtra(EXTRA_RECOVER_PENDING, true);
        ContextCompat.startForegroundService(context, intent);
    }

    public static void cancelTask(Context context, String txId) {
        TxTaskStore.markCancelled(context, txId);
        clearTaskNotifications(context, txId);
    }

    /**
     * Executes a native call with a timeout. If the call takes longer than NATIVE_CALL_TIMEOUT_MS,
     * it will be cancelled and a TimeoutException will be thrown.
     */
    private String executeNativeCallWithTimeout(java.util.concurrent.Callable<String> task, String errorMessage) throws Exception {
        java.util.concurrent.ExecutorService timeoutExecutor = Executors.newSingleThreadExecutor();
        try {
            Future<String> future = timeoutExecutor.submit(task);
            try {
                return future.get(NATIVE_CALL_TIMEOUT_MS, TimeUnit.MILLISECONDS);
            } catch (TimeoutException e) {
                future.cancel(true);
                throw new IllegalStateException(errorMessage + " (timed out after " + (NATIVE_CALL_TIMEOUT_MS / 60000) + " minutes)", e);
            } catch (java.util.concurrent.ExecutionException e) {
                // Unwrap: callers and logs need the real cause, not the wrapper.
                Throwable cause = e.getCause();
                if (cause instanceof Exception) throw (Exception) cause;
                if (cause instanceof Error) throw (Error) cause;
                throw new IllegalStateException(errorMessage + ": " + e.getMessage(), e);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw e;
            }
        } finally {
            timeoutExecutor.shutdownNow();
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
        String targetTxId = null;
        int scheduled = 0;

        if (intent == null || intent.getBooleanExtra(EXTRA_RECOVER_PENDING, false)) {
            scheduled = scheduleRecovery();
            if (scheduled > 0) {
                List<TxTaskStore.TaskItem> recoverable = TxTaskStore.getRecoverableTasks(getApplicationContext());
                if (!recoverable.isEmpty()) {
                    targetTxId = recoverable.get(0).id;
                }
            }
        } else {
            String txId = intent.getStringExtra("tx_id");
            if (txId != null && !txId.trim().isEmpty()) {
                targetTxId = txId.trim();
                scheduled = scheduleTaskById(targetTxId) ? 1 : 0;
            } else {
                scheduled = scheduleRecovery();
                if (scheduled > 0) {
                    List<TxTaskStore.TaskItem> recoverable = TxTaskStore.getRecoverableTasks(getApplicationContext());
                    if (!recoverable.isEmpty()) {
                        targetTxId = recoverable.get(0).id;
                    }
                }
            }
        }

        if (scheduled <= 0) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                stopForeground(STOP_FOREGROUND_REMOVE);
            } else {
                stopForeground(true);
            }
            stopSelf();
            return START_NOT_STICKY;
        }

        Notification notification = buildOngoingNotification("Processing transaction...", targetTxId);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(ONGOING_NOTIFICATION_ID, notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC);
        } else {
            startForeground(ONGOING_NOTIFICATION_ID, notification);
        }
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        executor.shutdown();
    }

    private synchronized int scheduleRecovery() {
        List<TxTaskStore.TaskItem> recoverable = TxTaskStore.getRecoverableTasks(getApplicationContext());
        int scheduled = 0;
        for (TxTaskStore.TaskItem item : recoverable) {
            if (scheduleTaskById(item.id)) {
                scheduled++;
            }
        }
        return scheduled;
    }

    private synchronized boolean scheduleTaskById(String txId) {
        if (txId == null || txId.isEmpty()) {
            return false;
        }
        if (runningTaskIds.contains(txId)) {
            return false;
        }
        TxTaskStore.TaskItem task = TxTaskStore.getTaskById(getApplicationContext(), txId);
        if (task == null) {
            return false;
        }
        if (TxTaskStore.STATUS_SUCCESS.equals(task.status) || TxTaskStore.STATUS_FAILED.equals(task.status)) {
            return false;
        }

        runningTaskIds.add(txId);
        activeJobs.incrementAndGet();
        executor.execute(() -> processTask(txId));
        return true;
    }

    private void processTask(String txId) {
        TxTaskStore.TaskItem task = null;
        try {
            task = TxTaskStore.getTaskById(getApplicationContext(), txId);
            if (task == null) {
                return;
            }

            prepareWallet(task.walletId);

            switch (task.type) {
                case ACTION_SEND:
                    doSend(task);
                    break;
                case ACTION_TOKEN_SEND:
                    doTokenSend(task);
                    break;
                case ACTION_ENCRYPT:
                    doEncrypt(task);
                    break;
                case ACTION_DECRYPT:
                    doDecrypt(task);
                    break;
                case ACTION_STEALTH:
                    doStealth(task);
                    break;
                default:
                    TxTaskStore.markFailed(getApplicationContext(), task.id,
                            "Unknown transaction type", "Unknown transaction type: " + task.type);
                    notifyFailed(task.id, "Unknown transaction type");
                    break;
            }
        } catch (Throwable t) {
            String msg = t.getMessage() == null ? "Transaction failed" : t.getMessage();
            TxTaskStore.markFailed(getApplicationContext(), txId, msg, msg);
            if (task != null && ACTION_STEALTH.equals(task.type)) {
                updateStealthTaskFinalFailure(getApplicationContext(), task.id, msg);
            }
            notifyFailed(txId, msg);
            postResultNotification("Transaction Failed", msg, txId, null);
        } finally {
            finishJob(txId);
        }
    }

    private void doSend(TxTaskStore.TaskItem task) throws Exception {
        String txId = task.id;
        String to = TxInputValidator.requireRecipient(task.to);
        long amountRaw = TxInputValidator.requireAmountRaw(task.amountRaw);
        String message = task.message;

        setTaskProgress(task, "1/4", "Loading wallet info...");
        JSONObject info = new JSONObject(OctraNative.getInstance().getWalletInfo());
        if (info.has("error")) {
            throw new IllegalStateException(info.optString("error", "Wallet info not available"));
        }

        String rpcUrl = info.optString("rpc_url", UrlSecurityValidator.DEFAULT_RPC);
        String address = info.getString("address");

        setTaskProgress(task, "2/4", "Fetching nonce...");
        int nonce = fetchNonce(rpcUrl, address);

        setTaskProgress(task, "3/4", "Signing transaction...");
        String txJson = executeNativeCallWithTimeout(
                () -> OctraNative.getInstance().signTransaction(
                        to, String.valueOf(amountRaw), nonce + 1,
                        (message == null || message.isEmpty()) ? null : message),
                "Failed to sign transaction");
        JSONObject tx = new JSONObject(txJson);
        if (tx.has("error")) {
            throw new IllegalStateException(tx.optString("error", "Failed to sign transaction"));
        }

        setTaskProgress(task, "4/4", "Submitting transaction...");
        String txHash = submitSignedTx(rpcUrl, tx);
        setTaskPendingFinal(task, txHash, "Waiting for final confirmation...");

        FinalStatus finalStatus = waitForFinalStatus(task, rpcUrl, txHash, null);
        if (finalStatus.success) {
            String messageText = "Transaction confirmed";
            TxTaskStore.markSuccess(getApplicationContext(), txId, txHash, messageText);
            notifySuccess(txId, messageText, txHash);
            postResultNotification("Send Successful", "Hash: " + abbreviate(txHash), txId, txHash);
        } else {
            String fail = finalStatus.message == null ? "Transaction failed" : finalStatus.message;
            TxTaskStore.markFailed(getApplicationContext(), txId, fail, fail);
            notifyFailed(txId, fail);
            postResultNotification("Send Failed", fail, txId, txHash);
        }
    }

    private void doTokenSend(TxTaskStore.TaskItem task) throws Exception {
        String txId = task.id;
        TokenMeta meta = TokenMeta.fromMessage(task.message);
        if (meta == null || meta.tokenAddress.isEmpty()) {
            throw new IllegalStateException("Token metadata is missing");
        }

        String to = !meta.to.isEmpty() ? meta.to : task.to;
        long amountRaw = TxInputValidator.requireAmountRaw(meta.amountRaw);

        if (to.isEmpty()) {
            throw new IllegalStateException("Recipient address is missing");
        }
        if (amountRaw <= 0L) {
            throw new IllegalStateException("Amount must be greater than 0");
        }

        setTaskProgress(task, "1/4", "Loading wallet info...");
        JSONObject info = new JSONObject(OctraNative.getInstance().getWalletInfo());
        if (info.has("error")) {
            throw new IllegalStateException(info.optString("error", "Wallet info not available"));
        }

        String rpcUrl = info.optString("rpc_url", UrlSecurityValidator.DEFAULT_RPC);
        String address = info.getString("address");

        setTaskProgress(task, "2/4", "Fetching nonce...");
        int nonce = fetchNonce(rpcUrl, address);

        setTaskProgress(task, "3/4", "Signing token transfer...");
        String txJson = executeNativeCallWithTimeout(
                () -> OctraNative.getInstance().signContractCallTx(
                        meta.tokenAddress, to, String.valueOf(amountRaw), nonce + 1, meta.feeOu),
                "Failed to sign token transfer");
        JSONObject tx = new JSONObject(txJson);
        if (tx.has("error")) {
            throw new IllegalStateException(tx.optString("error", "Failed to sign token transfer"));
        }

        setTaskProgress(task, "4/4", "Submitting transaction...");
        String txHash = submitSignedTx(rpcUrl, tx);
        setTaskPendingFinal(task, txHash, "Waiting for final confirmation...");

        FinalStatus finalStatus = waitForFinalStatus(task, rpcUrl, txHash, null);
        if (finalStatus.success) {
            String messageText = "Token transfer confirmed";
            TxTaskStore.markSuccess(getApplicationContext(), txId, txHash, messageText);
            notifySuccess(txId, messageText, txHash);
            postResultNotification("Token Transfer Successful", "Hash: " + abbreviate(txHash), txId, txHash);
        } else {
            String fail = finalStatus.message == null ? "Token transfer failed" : finalStatus.message;
            TxTaskStore.markFailed(getApplicationContext(), txId, fail, fail);
            notifyFailed(txId, fail);
            postResultNotification("Token Transfer Failed", fail, txId, txHash);
        }
    }

    private static final class TokenMeta {
        final String tokenAddress;
        final String tokenSymbol;
        final String to;
        final String amountRaw;
        final String feeOu;

        private TokenMeta(String tokenAddress, String tokenSymbol, String to, String amountRaw, String feeOu) {
            this.tokenAddress = tokenAddress == null ? "" : tokenAddress.trim();
            this.tokenSymbol = tokenSymbol == null ? "" : tokenSymbol.trim();
            this.to = to == null ? "" : to.trim();
            this.amountRaw = amountRaw == null ? "0" : amountRaw.trim();
            this.feeOu = feeOu == null || feeOu.trim().isEmpty() ? "1000" : feeOu.trim();
        }

        static TokenMeta fromMessage(String message) {
            if (message == null || message.trim().isEmpty()) {
                return null;
            }
            try {
                JSONObject obj = new JSONObject(message);
                return new TokenMeta(
                        obj.optString("token_address", ""),
                        obj.optString("token_symbol", ""),
                        obj.optString("to", ""),
                        obj.optString("amount_raw", "0"),
                        obj.optString("fee", "1000")
                );
            } catch (Exception ignored) {
                return null;
            }
        }
    }

    private void doEncrypt(TxTaskStore.TaskItem task) throws Exception {
        String txId = task.id;
        long amountRaw = TxInputValidator.requireAmountRaw(task.amountRaw);

        setTaskProgress(task, "1/5", "Loading wallet info...");
        JSONObject info = new JSONObject(OctraNative.getInstance().getWalletInfo());
        if (info.has("error")) {
            throw new IllegalStateException(info.optString("error", "Wallet info not available"));
        }

        String rpcUrl = info.optString("rpc_url", UrlSecurityValidator.DEFAULT_RPC);
        String address = info.getString("address");

        setTaskProgress(task, "2/5", "Registering PVAC key...");
        ensurePvacRegistered(rpcUrl, address);

        setTaskProgress(task, "3/5", "Fetching nonce...");
        int nonce = fetchNonce(rpcUrl, address);

        setTaskProgress(task, "4/5", "Signing encrypt transaction...");
        String txJson = executeNativeCallWithTimeout(
                () -> OctraNative.getInstance().signEncryptTx(
                        String.valueOf(amountRaw), nonce + 1, "", "", "", ""),
                "Failed to sign encrypt transaction");
        JSONObject tx = new JSONObject(txJson);
        if (tx.has("error")) {
            throw new IllegalStateException(tx.optString("error", "Failed to sign encrypt transaction"));
        }

        setTaskProgress(task, "5/5", "Submitting transaction...");
        String txHash = submitSignedTx(rpcUrl, tx);
        setTaskPendingFinal(task, txHash, "Waiting for final confirmation...");

        FinalStatus finalStatus = waitForFinalStatus(task, rpcUrl, txHash, null);
        if (finalStatus.success) {
            String messageText = "Encrypt confirmed";
            TxTaskStore.markSuccess(getApplicationContext(), txId, txHash, messageText);
            notifySuccess(txId, messageText, txHash);
            postResultNotification("Encrypt Successful", "Hash: " + abbreviate(txHash), txId, txHash);
        } else {
            String fail = finalStatus.message == null ? "Encrypt failed" : finalStatus.message;
            TxTaskStore.markFailed(getApplicationContext(), txId, fail, fail);
            notifyFailed(txId, fail);
            postResultNotification("Encrypt Failed", fail, txId, txHash);
        }
    }

    private void doDecrypt(TxTaskStore.TaskItem task) throws Exception {
        String txId = task.id;
        long amountRaw = TxInputValidator.requireAmountRaw(task.amountRaw);

        setTaskProgress(task, "1/5", "Loading wallet info...");
        JSONObject info = new JSONObject(OctraNative.getInstance().getWalletInfo());
        if (info.has("error")) {
            throw new IllegalStateException(info.optString("error", "Wallet info not available"));
        }

        String rpcUrl = info.optString("rpc_url", UrlSecurityValidator.DEFAULT_RPC);
        String address = info.getString("address");

        setTaskProgress(task, "2/5", "Registering PVAC key...");
        ensurePvacRegistered(rpcUrl, address);

        setTaskProgress(task, "3/5", "Fetching nonce...");
        int nonce = fetchNonce(rpcUrl, address);

        setTaskProgress(task, "4/5", "Signing decrypt transaction...");
        String txJson = executeNativeCallWithTimeout(
                () -> OctraNative.getInstance().signDecryptTx(
                        String.valueOf(amountRaw), nonce + 1, "", "", "", ""),
                "Failed to sign decrypt transaction");
        JSONObject tx = new JSONObject(txJson);
        if (tx.has("error")) {
            throw new IllegalStateException(tx.optString("error", "Failed to sign decrypt transaction"));
        }

        setTaskProgress(task, "5/5", "Submitting transaction...");
        String txHash = submitSignedTx(rpcUrl, tx);
        setTaskPendingFinal(task, txHash, "Waiting for final confirmation...");

        FinalStatus finalStatus = waitForFinalStatus(task, rpcUrl, txHash, null);
        if (finalStatus.success) {
            String messageText = "Decrypt confirmed";
            TxTaskStore.markSuccess(getApplicationContext(), txId, txHash, messageText);
            notifySuccess(txId, messageText, txHash);
            postResultNotification("Decrypt Successful", "Hash: " + abbreviate(txHash), txId, txHash);
        } else {
            String fail = finalStatus.message == null ? "Decrypt failed" : finalStatus.message;
            TxTaskStore.markFailed(getApplicationContext(), txId, fail, fail);
            notifyFailed(txId, fail);
            postResultNotification("Decrypt Failed", fail, txId, txHash);
        }
    }

    private void doStealth(TxTaskStore.TaskItem task) throws Exception {
        String txId = task.id;
        String stealthTaskId = txId;
        String to = TxInputValidator.requireRecipient(task.to);
        long amountRaw = TxInputValidator.requireAmountRaw(task.amountRaw);
        Context ctx = getApplicationContext();
        AtomicReference<StealthHeartbeatState> hbState = new AtomicReference<>(
                new StealthHeartbeatState("1/9", "Loading wallet info..."));
        Runnable stopHeartbeat = startStealthHeartbeat(stealthTaskId, hbState);

        try {
            updateStealthTask(ctx, stealthTaskId, "running", "1/9", "Loading wallet info...");
            setTaskProgress(task, "1/9", "Stealth: Loading wallet info...");
            JSONObject info = new JSONObject(OctraNative.getInstance().getWalletInfo());
            if (info.has("error")) {
                throw new IllegalStateException(info.optString("error", "Wallet info not available"));
            }

            String rpcUrl = info.optString("rpc_url", UrlSecurityValidator.DEFAULT_RPC);
            String address = info.getString("address");

            updateStealthHeartbeatState(hbState, "2/9", "Fetching recipient view pubkey...");
            updateStealthTask(ctx, stealthTaskId, "running", "2/9", "Fetching recipient view pubkey...");
            setTaskProgress(task, "2/9", "Stealth: Fetching view pubkey...");
            String theirViewPubkeyB64 = fetchViewPubkey(rpcUrl, to);

            updateStealthHeartbeatState(hbState, "3/9", "Ensuring PVAC registration...");
            updateStealthTask(ctx, stealthTaskId, "running", "3/9", "Ensuring PVAC registration...");
            setTaskProgress(task, "3/9", "Stealth: Registering PVAC...");
            ensurePvacRegistered(rpcUrl, address);

            updateStealthHeartbeatState(hbState, "4/9", "Fetching encrypted balance...");
            updateStealthTask(ctx, stealthTaskId, "running", "4/9", "Fetching encrypted balance...");
            setTaskProgress(task, "4/9", "Stealth: Fetching balance...");
            String encCipher = fetchEncryptedBalanceCipher(rpcUrl, address);
            if (encCipher == null || encCipher.trim().isEmpty() || "0".equals(encCipher.trim())) {
                throw new IllegalStateException("No encrypted balance available. Encrypt some balance first.");
            }

            updateStealthHeartbeatState(hbState, "5/9", "Preparing stealth cryptography...");
            updateStealthTask(ctx, stealthTaskId, "running", "5/9", "Preparing stealth cryptography...");
            setTaskProgress(task, "5/9", "Stealth: Preparing cryptography...");
            String prepJson = OctraNative.getInstance().stealthPrepare(theirViewPubkeyB64, to);
            JSONObject prep = new JSONObject(prepJson);
            if (prep.has("error")) {
                throw new IllegalStateException(prep.optString("error", "Stealth prepare failed"));
            }

            String ephPubB64 = prep.getString("eph_pub_b64");
            String sharedSecretB64 = prep.getString("shared_secret_b64");
            String stealthTagHex = prep.getString("stealth_tag_hex");
            String claimPubHex = prep.getString("claim_pub_hex");
            String blindingB64 = prep.getString("blinding_b64");

            byte[] sharedSecret = Base64.decode(sharedSecretB64, Base64.NO_WRAP);
            byte[] blinding = Base64.decode(blindingB64, Base64.NO_WRAP);
            String encAmountB64 = encryptStealthAmount(sharedSecret, amountRaw, blinding);

            updateStealthHeartbeatState(hbState, "6/9", "Fetching nonce...");
            updateStealthTask(ctx, stealthTaskId, "running", "6/9", "Fetching nonce...");
            setTaskProgress(task, "6/9", "Stealth: Fetching nonce...");
            int nonce = fetchNonce(rpcUrl, address);

            updateStealthHeartbeatState(hbState, "7/9", "Building proofs and signing...");
            updateStealthTask(ctx, stealthTaskId, "running", "7/9", "Building proofs and signing...");
            setTaskProgress(task, "7/9", "Stealth: Signing (can take minutes)...");
            updateOngoingNotification("Stealth: Building proofs (can take minutes)...");
            
            // Generate amount commitment (blinding is already base64 encoded)
            byte[] amtCommitBytes = OctraNative.getInstance().generateRandomBytes(32);
            String amtCommitB64 = OctraNative.getInstance().base64Encode(amtCommitBytes);
            
            String txJson = executeNativeCallWithTimeout(
                    () -> OctraNative.getInstance().signStealthSendTx(
                            String.valueOf(amountRaw), nonce + 1,
                            encCipher, ephPubB64, stealthTagHex,
                            claimPubHex, encAmountB64, blindingB64, amtCommitB64),
                    "Failed to build stealth transaction");
            JSONObject tx = new JSONObject(txJson);
            if (tx.has("error")) {
                throw new IllegalStateException(tx.optString("error", "Stealth transaction build failed"));
            }

            updateStealthHeartbeatState(hbState, "8/9", "Submitting transaction...");
            updateStealthTask(ctx, stealthTaskId, "running", "8/9", "Submitting transaction...");
            setTaskProgress(task, "8/9", "Stealth: Submitting transaction...");
            String txHash = submitSignedTx(rpcUrl, tx);
            updateStealthHeartbeatState(hbState, "9/9", "Waiting for final confirmation...");
            setTaskPendingFinal(task, txHash, "Stealth: Waiting for final confirmation...");

            FinalStatus finalStatus = waitForFinalStatus(task, rpcUrl, txHash, stealthTaskId);
            if (finalStatus.success) {
                String messageText = "Stealth transaction confirmed";
                TxTaskStore.markSuccess(ctx, txId, txHash, messageText);
                updateStealthTaskFinalSuccess(ctx, stealthTaskId, txHash, messageText);
                notifySuccess(txId, messageText, txHash);
                postResultNotification("Stealth Send Successful", "Hash: " + abbreviate(txHash), txId, txHash);
            } else {
                String fail = finalStatus.message == null ? "Stealth transaction failed" : finalStatus.message;
                TxTaskStore.markFailed(ctx, txId, fail, fail);
                updateStealthTaskFinalFailure(ctx, stealthTaskId, fail);
                notifyFailed(txId, fail);
                postResultNotification("Stealth Send Failed", fail, txId, txHash);
            }
        } finally {
            if (stopHeartbeat != null) {
                stopHeartbeat.run();
            }
        }
    }

    private FinalStatus waitForFinalStatus(
            TxTaskStore.TaskItem task,
            String rpcUrl,
            String txHash,
            String stealthTaskId
    ) {
        int consecutiveErrors = 0;
        final int MAX_CONSECUTIVE_ERRORS = 5;
        for (int i = 1; i <= MAX_CONFIRM_POLLS; i++) {
            FinalStatus status = queryFinalStatus(rpcUrl, txHash);
            if (status.done) {
                return status;
            }

            // Track consecutive RPC failures to exit early if network is down
            if (status.rpcError) {
                consecutiveErrors++;
            } else {
                consecutiveErrors = 0;
            }
            if (consecutiveErrors >= MAX_CONSECUTIVE_ERRORS) {
                FinalStatus errOut = new FinalStatus();
                errOut.done = true;
                errOut.success = false;
                errOut.message = "Network error. Transaction status could not be confirmed.";
                return errOut;
            }

            String message = "Waiting for final confirmation...";
            TxTaskStore.markPendingFinal(getApplicationContext(), task.id, txHash, "final", message);
            notifyProgress(task.id, message);
            if (stealthTaskId != null) {
                updateStealthTask(getApplicationContext(), stealthTaskId,
                        "running", "9/9", "Pending final confirmation...");
            }

            try {
                Thread.sleep(PollingSettingsStore.getIntervalMs(this));
            } catch (InterruptedException ignored) {
            }
        }

        FinalStatus timeout = new FinalStatus();
        timeout.done = true;
        timeout.success = false;
        timeout.isTimeout = true;
        timeout.message = "Transaction confirmation timeout. You can continue waiting or check later in history.";
        return timeout;
    }

    private FinalStatus queryFinalStatus(String rpcUrl, String txHash) {
        FinalStatus out = new FinalStatus();
        out.done = false;
        out.success = false;
        out.rpcError = false;
        out.message = "Transaction pending";

        try {
            JSONObject result = repo().fetchTransaction(rpcUrl, txHash);
            if (result == null) return out;

            JSONObject tx = result.optJSONObject("transaction");
            if (tx == null) tx = result;

            String status = extractStatusText(tx);
            String statusLower = status.toLowerCase(Locale.US);
            if (containsAny(statusLower, "reject", "rejected", "fail", "failed", "error", "invalid")) {
                out.done = true;
                out.success = false;
                
                String reason = status;
                if (reason.isEmpty()) reason = "Transaction rejected";
                
                // Humanize common errors
                if (statusLower.contains("nonce too low")) {
                    reason = "Transaction has an invalid sequence (nonce too low).";
                } else if (statusLower.contains("insufficient balance") || statusLower.contains("insufficient funds")) {
                    reason = "Insufficient balance to cover transaction and gas fees.";
                } else if (statusLower.contains("underpriced")) {
                    reason = "Gas fee is too low for current network conditions.";
                }
                
                out.message = reason;
                return out;
            }

            if (containsAny(statusLower, "success", "confirmed", "final", "committed", "accepted", "applied")) {
                out.done = true;
                out.success = true;
                out.message = "Transaction confirmed";
                return out;
            }
        } catch (Exception ignored) {
            out.rpcError = true;
        }

        return out;
    }

    private String extractStatusText(JSONObject tx) {
        if (tx == null) return "";
        StringBuilder combined = new StringBuilder();
        appendStatusField(combined, tx.optString("status", ""));
        appendStatusField(combined, tx.optString("tx_status", ""));
        appendStatusField(combined, tx.optString("state", ""));
        appendStatusField(combined, tx.optString("result", ""));
        appendStatusField(combined, tx.optString("final_status", ""));
        if (tx.optBoolean("rejected", false)) {
            appendStatusField(combined, "rejected");
        }
        if (tx.optBoolean("confirmed", false)) {
            appendStatusField(combined, "confirmed");
        }
        return combined.toString().trim();
    }

    private void appendStatusField(StringBuilder builder, String value) {
        if (value == null || value.trim().isEmpty()) return;
        if (builder.length() > 0) builder.append(" |");
        builder.append(' ').append(value.trim());
    }

    private boolean containsAny(String value, String... needles) {
        for (String needle : needles) {
            if (value.contains(needle)) return true;
        }
        return false;
    }

    private void setTaskProgress(TxTaskStore.TaskItem task, String step, String message) {
        TxTaskStore.markRunning(getApplicationContext(), task.id, step, message);
        notifyProgress(task.id, message);
    }

    private void setTaskPendingFinal(TxTaskStore.TaskItem task, String txHash, String message) {
        TxTaskStore.markPendingFinal(getApplicationContext(), task.id, txHash, "final", message);
        notifyProgress(task.id, message);
    }

    private void updateStealthTask(Context context, String id, String status, String step, String message) {
        StealthTaskManager.updateTask(context, id, status, step, message);
    }

    /** Bundled step+message state for atomic reads in heartbeat thread. */
    private static final class StealthHeartbeatState {
        final String step;
        final String message;
        StealthHeartbeatState(String step, String message) {
            this.step = step;
            this.message = message;
        }
    }

    private Runnable startStealthHeartbeat(String taskId,
                                           AtomicReference<StealthHeartbeatState> stateRef) {
        AtomicBoolean running = new AtomicBoolean(true);
        Thread t = new Thread(() -> {
            while (running.get()) {
                try {
                    Thread.sleep(STEALTH_HEARTBEAT_MS);
                } catch (InterruptedException ignored) {
                }
                StealthHeartbeatState snapshot = stateRef.get();
                StealthTaskManager.bumpActiveHeartbeat(
                        getApplicationContext(),
                        taskId,
                        StealthTaskManager.STATUS_RUNNING,
                        snapshot.step,
                        snapshot.message
                );
            }
        });
        t.setName("stealth-heartbeat-" + taskId);
        t.setDaemon(true);
        t.start();
        return () -> running.set(false);
    }

    private void updateStealthHeartbeatState(AtomicReference<StealthHeartbeatState> stateRef,
                                             String step,
                                             String message) {
        stateRef.set(new StealthHeartbeatState(
                step != null && !step.trim().isEmpty() ? step : stateRef.get().step,
                message != null && !message.trim().isEmpty() ? message : stateRef.get().message
        ));
    }

    private void updateStealthTaskFinalSuccess(Context context, String id, String txHash, String message) {
        StealthTaskManager.TaskItem done = StealthTaskManager.getTaskById(context, id);
        if (done == null) return;
        done.status = "success";
        done.step = "9/9";
        done.message = message;
        done.txHash = txHash == null ? "" : txHash;
        done.updatedAt = System.currentTimeMillis();
        StealthTaskManager.upsertTaskPublic(context, done);
    }

    private void updateStealthTaskFinalFailure(Context context, String id, String message) {
        StealthTaskManager.TaskItem failed = StealthTaskManager.getTaskById(context, id);
        if (failed == null) return;
        failed.status = "failed";
        failed.step = "9/9";
        failed.message = message;
        failed.updatedAt = System.currentTimeMillis();
        StealthTaskManager.upsertTaskPublic(context, failed);
    }

    private void prepareWallet(String walletId) throws Exception {
        String targetWallet = walletId == null || walletId.trim().isEmpty() ? "default" : walletId;
        File walletDir = WalletProfileStore.getWalletDir(getApplicationContext(), targetWallet);

        OctraNative nativeBridge = OctraNative.getInstance();
        nativeBridge.lockWallet();
        nativeBridge.init(walletDir.getAbsolutePath());

        if (nativeBridge.hasEncryptedWallet() && !nativeBridge.isWalletLoaded()) {
            String pin = PinStore.getDefaultPin(getApplicationContext());
            if (pin == null || !pin.matches("\\d{6}")) {
                throw new IllegalStateException("Wallet not loaded. Please unlock wallet first.");
            }

            String unlockRes = nativeBridge.unlockWallet(pin);
            JSONObject unlockJson = new JSONObject(unlockRes);
            if (unlockJson.has("error")) {
                throw new IllegalStateException(unlockJson.optString("error", "Wallet not loaded. Please unlock wallet first."));
            }
        }

        if (!nativeBridge.isWalletLoaded()) {
            throw new IllegalStateException("Wallet not loaded. Please unlock wallet first.");
        }
    }

    private static final class FinalStatus {
        boolean done;
        boolean success;
        boolean rpcError;
        boolean isTimeout;
        String message;
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm == null) return;

            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID, "Transaction Processing",
                    NotificationManager.IMPORTANCE_LOW);
            channel.setDescription("Ongoing transaction processing notifications");
            nm.createNotificationChannel(channel);

            NotificationChannel alertChannel = new NotificationChannel(
                    CHANNEL_ALERT_ID, "Transaction Alerts",
                    NotificationManager.IMPORTANCE_HIGH);
            alertChannel.setDescription("Transaction result and stealth progress alerts");
            alertChannel.enableVibration(true);
            nm.createNotificationChannel(alertChannel);
        }
    }

    private boolean hasNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                    == android.content.pm.PackageManager.PERMISSION_GRANTED;
        }
        return true;
    }

    private Notification buildOngoingNotification(String text, String txId) {
        Intent notifIntent;
        TxTaskStore.TaskItem task = TxTaskStore.getTaskById(getApplicationContext(), txId);
        if (task != null && ACTION_STEALTH.equals(task.type)) {
            notifIntent = new Intent(this, StealthTaskDetailActivity.class);
            notifIntent.putExtra("task_id", txId);
        } else if (task != null) {
            notifIntent = new Intent(this, TxProgressActivity.class);
            notifIntent.putExtra(TxProgressActivity.EXTRA_TX_ID, txId);
            notifIntent.putExtra(TxProgressActivity.EXTRA_TX_TYPE, task.type);
        } else {
            notifIntent = new Intent(this, MainActivity.class);
        }
        notifIntent.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        int requestCode = txId == null ? 0 : resultNotificationIdForTask(txId);
        PendingIntent pi = PendingIntent.getActivity(this, requestCode, notifIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        return new NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle("Octra Wallet")
                .setContentText(text)
                .setOngoing(true)
                .setContentIntent(pi)
                .build();
    }

    private void updateOngoingNotification(String text) {
        updateOngoingNotification(text, null);
    }

    private void updateOngoingNotification(String text, String txId) {
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm != null) {
            String targetId = txId;
            if (targetId == null || targetId.trim().isEmpty()) {
                synchronized (this) {
                    if (!runningTaskIds.isEmpty()) {
                        targetId = runningTaskIds.iterator().next();
                    }
                }
            }
            nm.notify(ONGOING_NOTIFICATION_ID, buildOngoingNotification(text, targetId));
        }
    }

    private void postResultNotification(String title, String text, String txId, String txHash) {
        if (!hasNotificationPermission()) return;

        if (TxTaskStore.wasTaskOpened(getApplicationContext(), txId)) {
            NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm != null) {
                nm.cancel(resultNotificationIdForTask(txId));
            }
            return;
        }

        TxTaskStore.TaskItem task = TxTaskStore.getTaskById(getApplicationContext(), txId);
        int notificationId = resultNotificationIdForTask(txId);

        Intent notifIntent;
        if (task != null && ACTION_STEALTH.equals(task.type)) {
            notifIntent = new Intent(this, StealthTaskDetailActivity.class);
            notifIntent.putExtra("task_id", txId);
        } else {
            notifIntent = new Intent(this, TxProgressActivity.class);
            notifIntent.putExtra(TxProgressActivity.EXTRA_TX_ID, txId);
            if (task != null) {
                notifIntent.putExtra(TxProgressActivity.EXTRA_TX_TYPE, task.type);
            }
        }
        if (txHash != null) {
            notifIntent.putExtra("tx_hash", txHash);
        }
        notifIntent.putExtra(EXTRA_RESULT_NOTIFICATION_ID, notificationId);
        notifIntent.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);

        PendingIntent pi = PendingIntent.getActivity(this, notificationId, notifIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        Notification n = new NotificationCompat.Builder(this, CHANNEL_ALERT_ID)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(title)
                .setContentText(text)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setContentIntent(pi)
                .build();

        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm != null) nm.notify(notificationId, n);
    }

    private void finishJob(String txId) {
        synchronized (this) {
            runningTaskIds.remove(txId);
        }

        int remaining = activeJobs.decrementAndGet();
        if (remaining < 0) {
            activeJobs.set(0);
        }

        scheduleRecovery();

        int totalRunning = activeJobs.get();
        if (totalRunning <= 0) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                stopForeground(STOP_FOREGROUND_REMOVE);
            } else {
                stopForeground(true);
            }
            NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm != null && !TxTaskStore.hasRecoverableTasks(getApplicationContext())) {
                nm.cancel(ONGOING_NOTIFICATION_ID);
            }
            stopSelf();
        } else {
            updateOngoingNotification("Processing transaction...");
        }
    }

    private void notifyProgress(String txId, String message) {
        updateOngoingNotification(message, txId);
        TxCallback cb = sCallback;
        if (cb != null) {
            cb.onTxProgress(txId, message);
        }
    }

    private void notifySuccess(String txId, String message, String txHash) {
        TxCallback cb = sCallback;
        if (cb != null) cb.onTxSuccess(txId, message, txHash);
    }

    private void notifyFailed(String txId, String message) {
        TxCallback cb = sCallback;
        if (cb != null) cb.onTxFailed(txId, message);
    }

    private void notifyTimeout(String txId, String message) {
        TxCallback cb = sCallback;
        if (cb != null) cb.onTxTimeout(txId, message);
    }

    private String abbreviate(String s) {
        if (s == null) return "";
        return s.length() > 20 ? s.substring(0, 10) + "..." + s.substring(s.length() - 6) : s;
    }

    private int fetchNonce(String rpcUrl, String address) throws Exception {
        return repo().fetchNonce(rpcUrl, address);
    }

    private String submitSignedTx(String rpcUrl, JSONObject tx) throws Exception {
        return repo().submitTx(rpcUrl, tx);
    }

    private void ensurePvacRegistered(String rpcUrl, String address) throws Exception {
        repo().ensurePvacRegistered(rpcUrl, address);
    }

    private String fetchViewPubkey(String rpcUrl, String address) throws Exception {
        return repo().fetchViewPubkey(rpcUrl, address);
    }

    private String fetchEncryptedBalanceCipher(String rpcUrl, String address) throws Exception {
        return repo().fetchEncryptedBalance(rpcUrl, address);
    }
    private static String encryptStealthAmount(byte[] sharedSecret, long amount, byte[] blinding)
            throws Exception {
        byte[] plaintext = new byte[40];
        ByteBuffer bb = ByteBuffer.wrap(plaintext).order(ByteOrder.LITTLE_ENDIAN);
        bb.putLong(amount);
        System.arraycopy(blinding, 0, plaintext, 8, 32);

        byte[] nonce = new byte[12];
        new SecureRandom().nextBytes(nonce);

        SecretKeySpec keySpec = new SecretKeySpec(sharedSecret, "AES");
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        GCMParameterSpec gcmSpec = new GCMParameterSpec(128, nonce);
        cipher.init(Cipher.ENCRYPT_MODE, keySpec, gcmSpec);
        byte[] ciphertextAndTag = cipher.doFinal(plaintext);

        byte[] output = new byte[68];
        System.arraycopy(nonce, 0, output, 0, 12);
        System.arraycopy(ciphertextAndTag, 0, output, 12, 56);

        return Base64.encodeToString(output, Base64.NO_WRAP);
    }
}
