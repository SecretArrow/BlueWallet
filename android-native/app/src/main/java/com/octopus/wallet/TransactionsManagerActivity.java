package com.octopus.wallet;

import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.core.app.NotificationManagerCompat;
import androidx.recyclerview.widget.DiffUtil;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.regex.Pattern;

import org.json.JSONObject;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class TransactionsManagerActivity extends BaseTxActivity {

    private static final long REFRESH_INTERVAL_MS = 5_000L;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable refreshRunnable = this::safeRefresh;
    private final List<TaskSnapshot> currentList = new ArrayList<>();
    private final ExecutorService bgExecutor = Executors.newSingleThreadExecutor();

    private RecyclerView recyclerView;
    private TextView emptyText;
    private TasksAdapter adapter;
    private boolean resumed = false;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_transactions_manager);
        setupToolbar(R.id.tx_manager_toolbar, "Transactions Manager");

        emptyText = findViewById(R.id.tx_manager_empty);
        recyclerView = findViewById(R.id.tx_manager_recycler);

        if (recyclerView != null) {
            recyclerView.setLayoutManager(new LinearLayoutManager(this));
            adapter = new TasksAdapter();
            recyclerView.setAdapter(adapter);
        }

        safeRefresh();
    }

    @Override
    protected void onResume() {
        super.onResume();
        resumed = true;
        safeRefresh();
    }

    @Override
    protected void onPause() {
        super.onPause();
        resumed = false;
        handler.removeCallbacks(refreshRunnable);
    }

    @Override
    protected void onDestroy() {
        handler.removeCallbacks(refreshRunnable);
        bgExecutor.shutdown();
        super.onDestroy();
    }

    // ── Refresh logic ──────────────────────────────────────────────────────

    private void safeRefresh() {
        if (isFinishing() || isDestroyed()) return;

        bgExecutor.execute(() -> {
            List<TaskSnapshot> fresh = loadSnapshots();
            handler.post(() -> {
                if (isFinishing() || isDestroyed()) return;
                applyDiff(fresh);
                if (emptyText != null) {
                    emptyText.setVisibility(fresh.isEmpty() ? View.VISIBLE : View.GONE);
                }
                if (recyclerView != null) {
                    recyclerView.setVisibility(fresh.isEmpty() ? View.GONE : View.VISIBLE);
                }
                scheduleNextRefresh(fresh);
            });
        });
    }

    private void scheduleNextRefresh(List<TaskSnapshot> list) {
        handler.removeCallbacks(refreshRunnable);
        if (!resumed) return;
        boolean hasActive = false;
        for (TaskSnapshot s : list) {
            if (s.active) { hasActive = true; break; }
        }
        if (hasActive) {
            handler.postDelayed(refreshRunnable, REFRESH_INTERVAL_MS);
        }
    }

    // ── Data loading ───────────────────────────────────────────────────────

    private List<TaskSnapshot> loadSnapshots() {
        List<TaskSnapshot> out = new ArrayList<>();
        try {
            List<TxTaskStore.TaskItem> txTasks = TxTaskStore.getAllTasks(getApplicationContext());
            if (txTasks != null) {
                for (TxTaskStore.TaskItem t : txTasks) {
                    if (t == null || t.id == null || t.id.trim().isEmpty()) continue;
                    try {
                        out.add(TaskSnapshot.fromTxTask(t));
                    } catch (Exception ignored) {
                        // Skip corrupt entries
                    }
                }
            }
        } catch (Exception ignored) {
        }
        return out;
    }

    private static String abbreviateHash(String hash) {
        if (hash == null || hash.length() <= 20) return hash == null ? "" : hash;
        return hash.substring(0, 10) + "..." + hash.substring(hash.length() - 8);
    }

    // ── DiffUtil-based list update ─────────────────────────────────────────

    private void applyDiff(List<TaskSnapshot> newList) {
        if (isFinishing() || isDestroyed()) return;
        DiffUtil.DiffResult diff = DiffUtil.calculateDiff(new DiffUtil.Callback() {
            @Override public int getOldListSize() { return currentList.size(); }
            @Override public int getNewListSize() { return newList.size(); }
            @Override public boolean areItemsTheSame(int oldPos, int newPos) {
                return currentList.get(oldPos).id.equals(newList.get(newPos).id);
            }
            @Override public boolean areContentsTheSame(int oldPos, int newPos) {
                return currentList.get(oldPos).equals(newList.get(newPos));
            }
        });
        currentList.clear();
        currentList.addAll(newList);
        if (adapter != null) {
            diff.dispatchUpdatesTo(adapter);
        }
    }

    // ── Item click ─────────────────────────────────────────────────────────

    private void openDetail(TaskSnapshot snap) {
        if (snap == null || snap.id.isEmpty()) return;
        try {
            NotificationManagerCompat.from(this)
                    .cancel(TxForegroundService.resultNotificationIdForTask(snap.id));
        } catch (Exception ignored) {
        }
        try {
            if ("stealth".equals(snap.type)) {
                Intent intent = new Intent(this, StealthTaskDetailActivity.class);
                intent.putExtra("task_id", snap.id);
                startActivity(intent);
            } else {
                Intent intent = new Intent(this, TxProgressActivity.class);
                intent.putExtra(TxProgressActivity.EXTRA_TX_ID, snap.id);
                intent.putExtra(TxProgressActivity.EXTRA_TX_TYPE, snap.type);
                startActivity(intent);
            }
        } catch (Exception e) {
            showError("Cannot open transaction detail");
        }
    }

    // ── Immutable snapshot ─────────────────────────────────────────────────

    static final class TaskSnapshot {
        final String id;
        final String type;
        final String typeLabel;
        final String to;
        final String amountFormatted;
        final String statusLabel;
        final String step;
        final String message;
        final String txHash;
        final String updatedLabel;
        final boolean active;
        final int statusColor; // 0 = neutral, 1 = success, -1 = failed

        private TaskSnapshot(String id, String type, String typeLabel, String to,
                             String amountFormatted, String statusLabel, String step,
                             String message, String txHash, String updatedLabel,
                             boolean active, int statusColor) {
            this.id = id;
            this.type = type;
            this.typeLabel = typeLabel;
            this.to = to;
            this.amountFormatted = amountFormatted;
            this.statusLabel = statusLabel;
            this.step = step;
            this.message = message;
            this.txHash = txHash;
            this.updatedLabel = updatedLabel;
            this.active = active;
            this.statusColor = statusColor;
        }

        static TaskSnapshot fromTxTask(TxTaskStore.TaskItem t) {
            boolean active = TxTaskStore.STATUS_QUEUED.equals(t.status)
                    || TxTaskStore.STATUS_RUNNING.equals(t.status)
                    || TxTaskStore.STATUS_PENDING_FINAL.equals(t.status);
            String label;
            int color = 0;
            if (TxTaskStore.STATUS_SUCCESS.equals(t.status)) {
                label = "Success"; color = 1;
            } else if (TxTaskStore.STATUS_FAILED.equals(t.status)) {
                label = "Failed"; color = -1;
            } else if (TxTaskStore.STATUS_QUEUED.equals(t.status)) {
                label = "Queued";
            } else if (TxTaskStore.STATUS_PENDING_FINAL.equals(t.status)) {
                label = "Confirming";
            } else {
                label = "Running";
            }
            String typeLabel = formatTypeLabel(t.type);
            return new TaskSnapshot(
                    safe(t.id),
                    safe(t.type),
                    typeLabel,
                    safe(t.to),
                    formatAmountWithTicker(t.amountRaw, t.type, extractTokenSymbol(t.message)),
                    label,
                    safe(t.step),
                    safe(t.progressMessage),
                    safe(t.txHash),
                    formatTime(t.updatedAt),
                    active,
                    color
            );
        }

        private static String formatTypeLabel(String type) {
            if (type == null) return "Unknown";
            switch (type) {
                case "send": return "Send";
                case "token_send": return "Token Transfer";
                case "stealth": return "Stealth Send";
                case "encrypt": return "Encrypt Balance";
                case "decrypt": return "Decrypt Balance";
                default: return type;
            }
        }

        @Override
        public boolean equals(Object o) {
            if (this == o) return true;
            if (!(o instanceof TaskSnapshot)) return false;
            TaskSnapshot s = (TaskSnapshot) o;
            return id.equals(s.id)
                    && type.equals(s.type)
                    && statusLabel.equals(s.statusLabel)
                    && step.equals(s.step)
                    && message.equals(s.message)
                    && txHash.equals(s.txHash)
                    && updatedLabel.equals(s.updatedLabel);
        }

        @Override
        public int hashCode() {
            return id.hashCode();
        }

        private static String safe(String v) { return v == null ? "" : v; }

        private static String formatRaw(String raw) {
            try {
                long v = Long.parseLong(raw == null ? "0" : raw);
                BigDecimal bd = BigDecimal.valueOf(v, 6).setScale(6, RoundingMode.DOWN).stripTrailingZeros();
                if (bd.scale() < 0) bd = bd.setScale(0);
                return bd.toPlainString();
            } catch (Exception e) { return "0"; }
        }

        private static String formatAmountWithTicker(String raw, String type, String tokenSymbol) {
            String amount = formatRaw(raw);
            if (tokenSymbol != null && !tokenSymbol.trim().isEmpty()) {
                return amount + " " + tokenSymbol.trim();
            }
            return amount + " OCT";
        }

        private static String extractTokenSymbol(String message) {
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

        private static String extractTokenAfterKey(String original, String lower, String key) {
            int idx = lower.indexOf(key);
            if (idx < 0) return "";
            String tail = original.substring(idx + key.length()).trim();
            if (tail.isEmpty()) return "";
            String[] parts = Pattern.compile("[^A-Za-z0-9_]+")
                    .split(tail, 2);
            return parts.length > 0 ? parts[0].trim() : "";
        }

        private static String formatTime(long ts) {
            if (ts <= 0L) return "-";
            return new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(new Date(ts));
        }
    }

    // ── RecyclerView Adapter ───────────────────────────────────────────────

    final class TasksAdapter extends RecyclerView.Adapter<TasksAdapter.VH> {

        @NonNull
        @Override
        public VH onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
            View v = LayoutInflater.from(parent.getContext())
                    .inflate(R.layout.item_transaction_task, parent, false);
            return new VH(v);
        }

        @Override
        public void onBindViewHolder(@NonNull VH holder, int position) {
            if (position < 0 || position >= currentList.size()) return;
            TaskSnapshot snap = currentList.get(position);
            holder.bind(snap);
            holder.itemView.setOnClickListener(v -> openDetail(snap));
        }

        @Override
        public int getItemCount() {
            return currentList.size();
        }

    final class VH extends RecyclerView.ViewHolder {
        final TextView typeText, toText, amountText, statusText,
                stepText, messageText, hashText, updatedText;
        final android.widget.Button cancelButton;

        VH(View v) {
            super(v);
            typeText = v.findViewById(R.id.tx_task_type);
            toText = v.findViewById(R.id.tx_task_to);
            amountText = v.findViewById(R.id.tx_task_amount);
            statusText = v.findViewById(R.id.tx_task_status);
            stepText = v.findViewById(R.id.tx_task_step);
            messageText = v.findViewById(R.id.tx_task_message);
            hashText = v.findViewById(R.id.tx_task_hash);
            updatedText = v.findViewById(R.id.tx_task_updated);
            cancelButton = v.findViewById(R.id.tx_task_cancel);
        }

            void bind(TaskSnapshot s) {
                if (s == null) return;
                try {
                    setText(typeText,    s.typeLabel);
                    setText(statusText,  s.statusLabel);
                    setText(amountText,  s.amountFormatted);
                    setText(updatedText, s.updatedLabel);

                    // To address - only show if present
                    if (toText != null) {
                        if (s.to.isEmpty()) {
                            toText.setVisibility(View.GONE);
                        } else {
                            toText.setVisibility(View.VISIBLE);
                            toText.setText("To: " + s.to);
                        }
                    }

                    // Step - only show if meaningful
                    if (stepText != null) {
                        if (s.step.isEmpty() || "0/0".equals(s.step)) {
                            stepText.setVisibility(View.GONE);
                        } else {
                            stepText.setVisibility(View.VISIBLE);
                            stepText.setText("Step: " + s.step);
                        }
                    }

                    // Message - only show if present
                    if (messageText != null) {
                        if (s.message.isEmpty()) {
                            messageText.setVisibility(View.GONE);
                        } else {
                            messageText.setVisibility(View.VISIBLE);
                            messageText.setText(s.message);
                        }
                    }

                    // Hash - only show if present
                    if (hashText != null) {
                        if (s.txHash.isEmpty()) {
                            hashText.setVisibility(View.GONE);
                        } else {
                            hashText.setVisibility(View.VISIBLE);
                            hashText.setText("Hash: " + abbreviateHash(s.txHash));
                        }
                    }

                    // Cancel button - only show for active tasks
                    if (cancelButton != null) {
                        if (s.active) {
                            cancelButton.setVisibility(View.VISIBLE);
                            cancelButton.setOnClickListener(v -> {
                                new androidx.appcompat.app.AlertDialog.Builder(TransactionsManagerActivity.this)
                                        .setTitle("Cancel Transaction")
                                        .setMessage("Are you sure you want to cancel this transaction?")
                                        .setPositiveButton("Cancel", (dialog, which) -> {
                                            TxForegroundService.cancelTask(getApplicationContext(), s.id);
                                            safeRefresh();
                                            showSuccess("Transaction cancelled");
                                        })
                                        .setNegativeButton("Keep", null)
                                        .show();
                            });
                        } else {
                            cancelButton.setVisibility(View.GONE);
                            cancelButton.setOnClickListener(null);
                        }
                    }

                    // Status color
                    if (statusText != null) {
                        int colorAttr;
                        if (s.statusColor > 0) {
                            colorAttr = com.google.android.material.R.attr.colorPrimary;
                        } else if (s.statusColor < 0) {
                            colorAttr = com.google.android.material.R.attr.colorError;
                        } else {
                            colorAttr = com.google.android.material.R.attr.colorOnSurface;
                        }
                        try {
                            statusText.setTextColor(com.google.android.material.color.MaterialColors.getColor(
                                    statusText, colorAttr));
                        } catch (Exception ignored) {
                        }
                    }
                } catch (Exception ignored) {
                }
            }

            private void setText(TextView tv, String text) {
                if (tv != null) tv.setText(text);
            }
        }
    }
}
