package com.octopus.wallet;

import android.app.Activity;
import android.view.View;

import androidx.annotation.NonNull;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;

/**
 * Centralized Window Insets / edge-to-edge helper (plan.txt § Android System
 * Bars, Insets and Edge-to-Edge).
 *
 * <p>Every Activity calls {@link #enableEdgeToEdge(Activity)} + {@link
 * #applySystemBars(View)} once in {@code onCreate()} after {@code
 * setContentView()}. Dialogs / BottomSheets call {@link
 * #applySystemBars(View)} on their root view. This keeps one consistent
 * policy instead of per-screen fixes: status bar (top), navigation bar /
 * gesture strip (bottom), display cutout, and IME (keyboard) are all handled;
 * initial padding is preserved so re-invocation never double-pads (rotation,
 * resize, keyboard show/hide).
 */
public final class InsetsHelper {

    private static final int TAG_APPLIED = 0x7f0b0001;

    private InsetsHelper() {
    }

    /** Draw edge-to-edge: content extends behind system bars, insets applied manually. */
    public static void enableEdgeToEdge(@NonNull Activity activity) {
        try {
            WindowCompat.setDecorFitsSystemWindows(activity.getWindow(), false);
        } catch (Exception ignored) {
            // Older devices / unusual window flags: non-fatal, layout still works.
        }
    }

    /**
     * Apply system-bars + cutout + IME insets to {@code root} as padding,
     * preserving the view's original padding. Idempotent: safe to call again
     * after rotation / resize. Pass {@code consumeIme=false} for scroll roots
     * that handle the keyboard themselves.
     */
    public static void applySystemBars(View root) {
        applySystemBars(root, true);
    }

    public static void applySystemBars(View root, boolean applyIme) {
        if (root == null) return;
        final int initLeft = root.getPaddingLeft();
        final int initTop = root.getPaddingTop();
        final int initRight = root.getPaddingRight();
        final int initBottom = root.getPaddingBottom();
        ViewCompat.setOnApplyWindowInsetsListener(root, (view, insets) -> {
            Insets bars = insets.getInsets(
                    WindowInsetsCompat.Type.systemBars()
                            | WindowInsetsCompat.Type.displayCutout());
            int imeBottom = 0;
            if (applyIme) {
                imeBottom = insets.getInsets(WindowInsetsCompat.Type.ime()).bottom;
            }
            int bottom = Math.max(bars.bottom, imeBottom);
            view.setPadding(
                    initLeft + bars.left,
                    initTop + bars.top,
                    initRight + bars.right,
                    initBottom + bottom);
            return insets;
        });
        ViewCompat.requestApplyInsets(root);
    }

    /**
     * Convenience: enable edge-to-edge and apply insets to the window content
     * root. One-liner for Activities without a custom root view.
     */
    public static void applyToActivity(@NonNull Activity activity) {
        enableEdgeToEdge(activity);
        try {
            View content = activity.findViewById(android.R.id.content);
            if (content != null) applySystemBars(content);
        } catch (Exception ignored) {
            // Never crash layout for insets.
        }
    }
}
