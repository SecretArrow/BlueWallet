package com.octopus.wallet;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.view.View;

import com.google.android.material.dialog.MaterialAlertDialogBuilder;
import com.google.android.material.snackbar.Snackbar;

/**
 * Centralized error/info display helper.
 *
 * Severity levels:
 *  - Info    → Snackbar SHORT   (e.g. "Address copied")
 *  - Warning → Snackbar LONG    (e.g. "This will be removed")
 *  - Error   → MaterialAlertDialog with "Copy Error" button
 *  - Retry   → Snackbar INDEFINITE with "Retry" action
 */
public final class ErrorDisplayHelper {

    /** Auto-clear clipboard after this many ms (30 seconds). */
    private static final long CLIPBOARD_CLEAR_DELAY_MS = 30_000L;

    private ErrorDisplayHelper() {}

    // ─── Info ──────────────────────────────────────────────────────────────

    /** Short Snackbar for neutral informational messages. */
    public static void showInfo(View root, String message) {
        if (root == null || message == null) return;
        Snackbar.make(root, message, Snackbar.LENGTH_SHORT).show();
    }

    // ─── Warning ───────────────────────────────────────────────────────────

    /** Long Snackbar for warnings (reversible / user should notice). */
    public static void showWarning(View root, String message) {
        if (root == null || message == null) return;
        Snackbar.make(root, message, Snackbar.LENGTH_LONG).show();
    }

    // ─── Error ─────────────────────────────────────────────────────────────

    /**
     * MaterialAlertDialog for errors the user MUST acknowledge.
     * Shows a "Copy Error" neutral button so the user can report issues.
     */
    public static void showError(Activity activity, String title, String message) {
        if (activity == null || activity.isFinishing() || activity.isDestroyed()) return;
        if (message == null) message = "An unknown error occurred.";
        final String finalMessage = message;
        activity.runOnUiThread(() -> {
            if (activity.isFinishing() || activity.isDestroyed()) return;
            new MaterialAlertDialogBuilder(activity)
                    .setTitle(title != null ? title : "Error")
                    .setMessage(finalMessage)
                    .setPositiveButton("OK", null)
                    .setNeutralButton("Copy Error", (d, w) ->
                            copyToClipboard(activity, finalMessage))
                    .show();
        });
    }

    /** Convenience — uses "Error" as the title. */
    public static void showError(Activity activity, String message) {
        showError(activity, "Error", message);
    }

    // ─── Retry ─────────────────────────────────────────────────────────────

    /**
     * Indefinite Snackbar with a "Retry" action button.
     * Ideal for network errors where the user can re-trigger the fetch.
     */
    public static void showRetryError(View root, String message, Runnable onRetry) {
        if (root == null || message == null) return;
        Snackbar snackbar = Snackbar.make(root, message, Snackbar.LENGTH_INDEFINITE);
        if (onRetry != null) {
            snackbar.setAction("Retry", v -> onRetry.run());
        }
        snackbar.show();
    }

    // ─── Clipboard helpers ─────────────────────────────────────────────────

    /**
     * Copy {@code text} to the clipboard and schedule an auto-clear after
     * {@link #CLIPBOARD_CLEAR_DELAY_MS} milliseconds.
     */
    public static void copyToClipboardWithAutoClear(Context context, String label, String text) {
        if (context == null) return;
        copyToClipboard(context, label, text);
        scheduleClipboardClear(context);
    }

    /** Overload that uses {@code "text"} as the clip label. */
    public static void copyToClipboard(Context context, String text) {
        copyToClipboard(context, "text", text);
    }

    private static void copyToClipboard(Context context, String label, String text) {
        if (context == null || text == null) return;
        ClipboardManager clipboard =
                (ClipboardManager) context.getSystemService(Context.CLIPBOARD_SERVICE);
        if (clipboard != null) {
            clipboard.setPrimaryClip(ClipData.newPlainText(label, text));
        }
    }

    /**
     * Schedule clearing the clipboard after {@link #CLIPBOARD_CLEAR_DELAY_MS}.
     * Call this immediately after placing sensitive data (keys, addresses) on the clipboard.
     */
    public static void scheduleClipboardClear(Context context) {
        if (context == null) return;
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            try {
                ClipboardManager clipboard =
                        (ClipboardManager) context.getSystemService(Context.CLIPBOARD_SERVICE);
                if (clipboard != null) {
                    clipboard.setPrimaryClip(ClipData.newPlainText("", ""));
                }
            } catch (Exception ignored) {
            }
        }, CLIPBOARD_CLEAR_DELAY_MS);
    }
}
