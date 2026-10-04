package com.octopus.wallet;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

public final class TxTaskStore {
    private static final String PREFS = "tx_tasks";
    private static final String KEY_ITEMS = "items";
    private static final String KEY_OPENED_TASK_IDS = "opened_task_ids";

    public static final String STATUS_QUEUED = "queued";
    public static final String STATUS_RUNNING = "running";
    public static final String STATUS_PENDING_FINAL = "pending_final";
    public static final String STATUS_SUCCESS = "success";
    public static final String STATUS_FAILED = "failed";

    public static final class TaskItem {
        public String id;
        public String type;
        public String walletId;
        public String to;
        public String amountRaw;
        public String message;
        public String status;
        public String step;
        public String progressMessage;
        public String txHash;
        public String errorMessage;
        public long createdAt;
        public long updatedAt;
    }

    private TxTaskStore() {
    }

    public static synchronized TaskItem enqueue(
            Context context,
            String id,
            String type,
            String walletId,
            String to,
            long amountRaw,
            String message
    ) {
        TaskItem task = new TaskItem();
        task.id = id;
        task.type = type;
        task.walletId = walletId == null ? "default" : walletId;
        task.to = to == null ? "" : to;
        task.amountRaw = String.valueOf(Math.max(0L, amountRaw));
        task.message = message == null ? "" : message;
        task.status = STATUS_QUEUED;
        task.step = "0/0";
        task.progressMessage = "Queued";
        task.txHash = "";
        task.errorMessage = "";
        task.createdAt = System.currentTimeMillis();
        task.updatedAt = task.createdAt;

        upsert(context, task);
        return task;
    }

    public static synchronized void markRunning(Context context, String id, String step, String progressMessage) {
        TaskItem task = getTaskById(context, id);
        if (task == null) return;
        task.status = STATUS_RUNNING;
        task.step = safe(step, task.step);
        task.progressMessage = safe(progressMessage, task.progressMessage);
        task.updatedAt = System.currentTimeMillis();
        upsert(context, task);
    }

    public static synchronized void updateProgress(Context context, String id, String step, String progressMessage) {
        TaskItem task = getTaskById(context, id);
        if (task == null) return;
        if (STATUS_QUEUED.equals(task.status)) {
            task.status = STATUS_RUNNING;
        }
        task.step = safe(step, task.step);
        task.progressMessage = safe(progressMessage, task.progressMessage);
        task.updatedAt = System.currentTimeMillis();
        upsert(context, task);
    }

    public static synchronized void markPendingFinal(
            Context context,
            String id,
            String txHash,
            String step,
            String progressMessage
    ) {
        TaskItem task = getTaskById(context, id);
        if (task == null) return;
        task.status = STATUS_PENDING_FINAL;
        task.txHash = txHash == null ? "" : txHash;
        task.step = safe(step, task.step);
        task.progressMessage = safe(progressMessage, task.progressMessage);
        task.updatedAt = System.currentTimeMillis();
        upsert(context, task);
    }

    public static synchronized void markSuccess(Context context, String id, String txHash, String progressMessage) {
        TaskItem task = getTaskById(context, id);
        if (task == null) return;
        task.status = STATUS_SUCCESS;
        task.txHash = txHash == null ? "" : txHash;
        task.progressMessage = safe(progressMessage, "Completed");
        task.errorMessage = "";
        task.updatedAt = System.currentTimeMillis();
        upsert(context, task);
    }

    public static synchronized void markFailed(Context context, String id, String progressMessage, String errorMessage) {
        TaskItem task = getTaskById(context, id);
        if (task == null) return;
        task.status = STATUS_FAILED;
        task.progressMessage = safe(progressMessage, "Failed");
        task.errorMessage = safe(errorMessage, progressMessage);
        task.updatedAt = System.currentTimeMillis();
        upsert(context, task);
    }

    public static synchronized void markCancelled(Context context, String id) {
        TaskItem task = getTaskById(context, id);
        if (task == null) return;
        task.status = STATUS_FAILED;
        task.progressMessage = "Cancelled by user";
        task.errorMessage = "Transaction was cancelled by user";
        task.updatedAt = System.currentTimeMillis();
        upsert(context, task);
    }

    public static synchronized TaskItem getTaskById(Context context, String id) {
        if (id == null || id.trim().isEmpty()) return null;
        List<TaskItem> items = readTasks(context.getApplicationContext());
        for (TaskItem item : items) {
            if (id.equals(item.id)) {
                return item;
            }
        }
        return null;
    }

    public static synchronized List<TaskItem> getRecoverableTasks(Context context) {
        List<TaskItem> items = readTasks(context.getApplicationContext());
        List<TaskItem> out = new ArrayList<>();
        for (TaskItem item : items) {
            if (STATUS_QUEUED.equals(item.status)
                    || STATUS_RUNNING.equals(item.status)
                    || STATUS_PENDING_FINAL.equals(item.status)) {
                out.add(item);
            }
        }
        out.sort((left, right) -> Long.compare(left.createdAt, right.createdAt));
        return out;
    }

    public static synchronized boolean hasRecoverableTasks(Context context) {
        return !getRecoverableTasks(context).isEmpty();
    }

    public static synchronized void markTaskOpened(Context context, String id) {
        if (id == null || id.trim().isEmpty()) return;
        SharedPreferences prefs = context.getApplicationContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        java.util.Set<String> current = prefs.getStringSet(KEY_OPENED_TASK_IDS, new java.util.HashSet<>());
        java.util.HashSet<String> updated = new java.util.HashSet<>(current == null ? new java.util.HashSet<>() : current);
        updated.add(id.trim());
        if (updated.size() > 500) {
            java.util.HashSet<String> trimmed = new java.util.HashSet<>();
            int count = 0;
            for (String value : updated) {
                trimmed.add(value);
                count++;
                if (count >= 300) break;
            }
            updated = trimmed;
        }
        prefs.edit().putStringSet(KEY_OPENED_TASK_IDS, updated).apply();
    }

    public static synchronized boolean wasTaskOpened(Context context, String id) {
        if (id == null || id.trim().isEmpty()) return false;
        SharedPreferences prefs = context.getApplicationContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        java.util.Set<String> current = prefs.getStringSet(KEY_OPENED_TASK_IDS, new java.util.HashSet<>());
        return current != null && current.contains(id.trim());
    }

    public static synchronized void clearTaskOpened(Context context, String id) {
        if (id == null || id.trim().isEmpty()) return;
        SharedPreferences prefs = context.getApplicationContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        java.util.Set<String> current = prefs.getStringSet(KEY_OPENED_TASK_IDS, new java.util.HashSet<>());
        java.util.HashSet<String> updated = new java.util.HashSet<>(current == null ? new java.util.HashSet<>() : current);
        if (updated.remove(id.trim())) {
            prefs.edit().putStringSet(KEY_OPENED_TASK_IDS, updated).apply();
        }
    }

    public static synchronized List<TaskItem> getAllTasks(Context context) {
        return readTasks(context.getApplicationContext());
    }

    public static synchronized void clearAll(Context context) {
        context.getApplicationContext()
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_ITEMS, "[]")
                .remove(KEY_OPENED_TASK_IDS)
                .apply();
    }

    private static synchronized void upsert(Context context, TaskItem task) {
        List<TaskItem> items = readTasks(context.getApplicationContext());
        boolean replaced = false;
        for (int i = 0; i < items.size(); i++) {
            if (items.get(i).id.equals(task.id)) {
                items.set(i, task);
                replaced = true;
                break;
            }
        }
        if (!replaced) {
            items.add(task);
        }
        items.sort(Comparator.comparingLong(item -> -item.updatedAt));
        if (items.size() > 200) {
            items = new ArrayList<>(items.subList(0, 200));
        }
        writeTasks(context.getApplicationContext(), items);
    }

    private static List<TaskItem> readTasks(Context context) {
        List<TaskItem> out = new ArrayList<>();
        try {
            SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
            String raw = prefs.getString(KEY_ITEMS, "[]");
            JSONArray arr = new JSONArray(raw == null ? "[]" : raw);
            for (int i = 0; i < arr.length(); i++) {
                JSONObject obj = arr.optJSONObject(i);
                if (obj == null) continue;
                String id = obj.optString("id", "").trim();
                String type = obj.optString("type", "").trim();
                if (id.isEmpty() || type.isEmpty()) continue;

                TaskItem item = new TaskItem();
                item.id = id;
                item.type = type;
                item.walletId = obj.optString("walletId", "default");
                item.to = obj.optString("to", "");
                item.amountRaw = obj.optString("amountRaw", "0");
                item.message = obj.optString("message", "");
                item.status = obj.optString("status", STATUS_QUEUED);
                item.step = obj.optString("step", "0/0");
                item.progressMessage = obj.optString("progressMessage", "Queued");
                item.txHash = obj.optString("txHash", "");
                item.errorMessage = obj.optString("errorMessage", "");
                item.createdAt = obj.optLong("createdAt", 0L);
                item.updatedAt = obj.optLong("updatedAt", item.createdAt);
                out.add(item);
            }
        } catch (Exception ignored) {
        }
        return out;
    }

    private static void writeTasks(Context context, List<TaskItem> items) {
        JSONArray arr = new JSONArray();
        for (TaskItem item : items) {
            JSONObject obj = new JSONObject();
            try {
                obj.put("id", item.id);
                obj.put("type", item.type);
                obj.put("walletId", item.walletId == null ? "default" : item.walletId);
                obj.put("to", item.to == null ? "" : item.to);
                obj.put("amountRaw", item.amountRaw == null ? "0" : item.amountRaw);
                obj.put("message", item.message == null ? "" : item.message);
                obj.put("status", item.status == null ? STATUS_QUEUED : item.status);
                obj.put("step", item.step == null ? "0/0" : item.step);
                obj.put("progressMessage", item.progressMessage == null ? "Queued" : item.progressMessage);
                obj.put("txHash", item.txHash == null ? "" : item.txHash);
                obj.put("errorMessage", item.errorMessage == null ? "" : item.errorMessage);
                obj.put("createdAt", item.createdAt);
                obj.put("updatedAt", item.updatedAt);
            } catch (Exception ignored) {
            }
            arr.put(obj);
        }

        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_ITEMS, arr.toString())
                .apply();
    }

    /**
     * Searches all stored tasks for one whose {@code txHash} field matches the given hash and
     * returns the token symbol embedded in its {@code message} (the raw JSON meta payload stored
     * at enqueue time for token-send tasks).  Returns an empty string when not found so callers
     * can safely ignore the result.
     */
    public static synchronized String getTokenSymbolByTxHash(Context context, String txHash) {
        if (txHash == null || txHash.trim().isEmpty()) return "";
        String normalised = txHash.trim();
        List<TaskItem> items = readTasks(context.getApplicationContext());
        for (TaskItem item : items) {
            if (normalised.equalsIgnoreCase(item.txHash == null ? "" : item.txHash.trim())) {
                return extractTokenSymbolFromMessage(item.message);
            }
        }
        return "";
    }

    /**
     * Extracts a token symbol from the raw message payload stored in a TaskItem.
     * The payload is either a JSON object containing {@code token_symbol} / {@code symbol}, or
     * a plain string with a "token:" / "symbol:" prefix.
     */
    private static String extractTokenSymbolFromMessage(String message) {
        if (message == null || message.trim().isEmpty()) return "";
        String text = message.trim();
        if (text.startsWith("{")) {
            try {
                JSONObject obj = new JSONObject(text);
                String sym = obj.optString("token_symbol", "");
                if (sym.isEmpty()) sym = obj.optString("symbol", "");
                if (sym.isEmpty()) sym = obj.optString("ticker", "");
                return sym == null ? "" : sym.trim();
            } catch (Exception ignored) {
            }
        }
        return "";
    }

    private static String safe(String value, String fallback) {
        if (value == null || value.trim().isEmpty()) return fallback == null ? "" : fallback;
        return value;
    }
}
