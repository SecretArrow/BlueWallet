package com.octopus.wallet;

import android.content.Context;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

public final class StealthTaskManager {
    private static final String PREFS = "stealth_tasks";
    private static final String KEY_TASKS = "items";

    public static final class TaskItem {
        public String id;
        public String to;
        public String amountRaw;
        public String status; // queued|running|success|failed
        public String step;
        public String message;
        public String txHash;
        public long createdAt;
        public long updatedAt;
    }

    public static final String STATUS_QUEUED = "queued";
    public static final String STATUS_RUNNING = "running";
    public static final String STATUS_SUCCESS = "success";
    public static final String STATUS_FAILED = "failed";

    private StealthTaskManager() {
    }

    public static String enqueueTask(Context context, String to, long amountRaw, String message) {
        Context appCtx = context.getApplicationContext();
        String id = "st_" + System.currentTimeMillis();

        TaskItem item = new TaskItem();
        item.id = id;
        item.to = to;
        item.amountRaw = String.valueOf(Math.max(0L, amountRaw));
        item.status = STATUS_QUEUED;
        item.step = "0/9";
        item.message = "Queued";
        item.txHash = "";
        item.createdAt = System.currentTimeMillis();
        item.updatedAt = item.createdAt;
        upsertTask(appCtx, item);

        TxForegroundService.startStealth(appCtx, id, to, amountRaw, message);
        return id;
    }

    public static List<TaskItem> getTasks(Context context) {
        List<TaskItem> list = readTasks(context.getApplicationContext());
        list.sort((a, b) -> Long.compare(b.updatedAt, a.updatedAt));
        return list;
    }

    /** Update a task's status fields. Called by TxForegroundService. */
    public static void updateTask(Context context, String id, String status, String step, String message) {
        synchronized (StealthTaskManager.class) {
            TaskItem item = getTaskById(context, id);
            if (item == null) return;
            item.status = normalizeStatus(status);
            item.step = step;
            item.message = message;
            item.updatedAt = System.currentTimeMillis();
            upsertTask(context, item);
        }
    }

    /**
     * Lightweight heartbeat updater to keep timestamps fresh while a task is running.
     * Does nothing if the task is already finished.
     * Enforces monotonicity: only writes step if incoming step number >= stored step number.
     */
    public static void bumpActiveHeartbeat(Context context, String id, String status, String step, String message) {
        synchronized (StealthTaskManager.class) {
            TaskItem item = getTaskById(context, id);
            if (item == null) return;
            if (isFinishedStatus(item.status)) return;

            // Monotonicity check: parse step numerator (e.g. "7" from "7/9") and only
            // update if incoming step >= stored step to prevent backward jumps.
            int incomingStepNum = parseStepNumerator(step);
            int storedStepNum = parseStepNumerator(item.step);
            if (incomingStepNum < storedStepNum) {
                // Only bump timestamp, do not overwrite step/message with stale values
                item.updatedAt = System.currentTimeMillis();
                upsertTask(context, item);
                return;
            }

            if (status != null && !status.trim().isEmpty()) {
                item.status = normalizeStatus(status);
            }
            if (step != null && !step.trim().isEmpty()) {
                item.step = step;
            }
            if (message != null && !message.trim().isEmpty()) {
                item.message = message;
            }
            item.updatedAt = System.currentTimeMillis();
            upsertTask(context, item);
        }
    }

    /** Parse the numerator from a step string like "7/9" → 7. Returns -1 on failure. */
    private static int parseStepNumerator(String step) {
        if (step == null || step.trim().isEmpty()) return -1;
        try {
            String trimmed = step.trim();
            int slashIdx = trimmed.indexOf('/');
            if (slashIdx > 0) {
                return Integer.parseInt(trimmed.substring(0, slashIdx));
            }
            return Integer.parseInt(trimmed);
        } catch (NumberFormatException e) {
            return -1;
        }
    }

    public static boolean isActiveStatus(String status) {
        String normalized = normalizeStatus(status);
        return STATUS_QUEUED.equals(normalized) || STATUS_RUNNING.equals(normalized);
    }

    public static boolean isFinishedStatus(String status) {
        return !isActiveStatus(status);
    }

    public static String normalizeStatus(String status) {
        String value = status == null ? "" : status.trim().toLowerCase();
        if (value.isEmpty()) return STATUS_QUEUED;
        if (value.contains("queue")) return STATUS_QUEUED;
        if (value.contains("run") || value.contains("pending")) return STATUS_RUNNING;
        if (value.contains("success") || value.contains("confirm") || value.contains("done") || value.contains("finish")) {
            return STATUS_SUCCESS;
        }
        if (value.contains("fail") || value.contains("error") || value.contains("reject") || value.contains("invalid") || value.contains("timeout")) {
            return STATUS_FAILED;
        }
        return STATUS_RUNNING;
    }

    public static synchronized void clearAll(Context context) {
        context.getApplicationContext()
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_TASKS, "[]")
                .apply();
    }

    /** Public wrapper for upserting a task. Called by TxForegroundService. */
    public static void upsertTaskPublic(Context context, TaskItem item) {
        upsertTask(context, item);
    }

    /** Public accessor for looking up a task by ID. */
    public static TaskItem getTaskById(Context context, String id) {
        for (TaskItem t : readTasks(context.getApplicationContext())) {
            if (t.id.equals(id)) return t;
        }
        return null;
    }

    private static List<TaskItem> readTasks(Context context) {
        try {
            String raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_TASKS, "[]");
            JSONArray arr = new JSONArray(raw == null ? "[]" : raw);
            List<TaskItem> out = new ArrayList<>();
            for (int i = 0; i < arr.length(); i++) {
                JSONObject o = arr.optJSONObject(i);
                if (o == null) continue;
                TaskItem t = new TaskItem();
                t.id = o.optString("id", "");
                t.to = o.optString("to", "");
                t.amountRaw = o.optString("amountRaw", "0");
                t.status = normalizeStatus(o.optString("status", STATUS_QUEUED));
                t.step = o.optString("step", "0/9");
                t.message = o.optString("message", "");
                t.txHash = o.optString("txHash", "");
                t.createdAt = o.optLong("createdAt", 0L);
                t.updatedAt = o.optLong("updatedAt", 0L);
                out.add(t);
            }
            return out;
        } catch (Exception e) {
            return new ArrayList<>();
        }
    }

    private static void writeTasks(Context context, List<TaskItem> tasks) {
        JSONArray arr = new JSONArray();
        for (TaskItem t : tasks) {
            JSONObject o = new JSONObject();
            try {
                o.put("id", t.id);
                o.put("to", t.to);
                o.put("amountRaw", t.amountRaw);
                o.put("status", normalizeStatus(t.status));
                o.put("step", t.step);
                o.put("message", t.message);
                o.put("txHash", t.txHash);
                o.put("createdAt", t.createdAt);
                o.put("updatedAt", t.updatedAt);
            } catch (Exception ignored) {
            }
            arr.put(o);
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_TASKS, arr.toString())
                .apply();
    }

    private static synchronized void upsertTask(Context context, TaskItem item) {
        item.status = normalizeStatus(item.status);
        List<TaskItem> tasks = readTasks(context);
        boolean found = false;
        for (int i = 0; i < tasks.size(); i++) {
            if (tasks.get(i).id.equals(item.id)) {
                tasks.set(i, item);
                found = true;
                break;
            }
        }
        if (!found) tasks.add(item);
        tasks.sort(Comparator.comparingLong(a -> -a.updatedAt));
        if (tasks.size() > 100) {
            tasks = tasks.subList(0, 100);
        }
        writeTasks(context, tasks);
    }
}
