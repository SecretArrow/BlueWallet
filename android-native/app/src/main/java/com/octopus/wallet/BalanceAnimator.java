package com.octopus.wallet;

import android.animation.ValueAnimator;
import android.view.animation.DecelerateInterpolator;
import android.widget.TextView;

import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * Animates OCT/token balance values in a TextView using a smooth count-up/count-down effect.
 *
 * Usage:
 * <pre>
 *   BalanceAnimator.animate(myTextView, 0L, 1_500_000L, 6, " OCT");
 * </pre>
 */
public final class BalanceAnimator {

    private static final long DURATION_MS = 700L;

    private BalanceAnimator() {}

    /**
     * Animate from {@code fromRaw} to {@code toRaw} micro-units with the given decimal places.
     *
     * @param tv       target TextView
     * @param fromRaw  start value in micro-units (e.g. 0)
     * @param toRaw    end value in micro-units
     * @param decimals decimal places (6 for OCT, variable for tokens)
     * @param suffix   text suffix such as " OCT" or " TOKEN"
     */
    public static void animate(TextView tv, long fromRaw, long toRaw, int decimals, String suffix) {
        if (tv == null) return;

        // Cancel any previously running animator on the same view
        Object tag = tv.getTag(R.id.balance_animator_tag);
        if (tag instanceof ValueAnimator) {
            ((ValueAnimator) tag).cancel();
        }

        if (fromRaw == toRaw) {
            tv.setText(format(toRaw, decimals) + (suffix != null ? suffix : ""));
            return;
        }

        ValueAnimator animator = ValueAnimator.ofFloat(0f, 1f);
        animator.setDuration(DURATION_MS);
        animator.setInterpolator(new DecelerateInterpolator());

        long delta = toRaw - fromRaw;
        animator.addUpdateListener(anim -> {
            float fraction = (float) anim.getAnimatedValue();
            long current = fromRaw + Math.round(delta * fraction);
            tv.setText(format(current, decimals) + (suffix != null ? suffix : ""));
        });

        tv.setTag(R.id.balance_animator_tag, animator);
        animator.start();
    }

    /** Convenience overload for OCT (6 decimals). */
    public static void animateOct(TextView tv, long fromRaw, long toRaw) {
        animate(tv, fromRaw, toRaw, 6, " OCT");
    }

    // ─── Formatting ────────────────────────────────────────────────────────

    private static String format(long raw, int decimals) {
        try {
            BigDecimal value = BigDecimal.valueOf(raw, decimals)
                    .setScale(Math.max(2, decimals), RoundingMode.DOWN)
                    .stripTrailingZeros();
            if (value.scale() < 0) value = value.setScale(0);
            // Keep at least 2 decimal places for readability
            if (value.scale() < 2) value = value.setScale(2, RoundingMode.DOWN);
            return value.toPlainString();
        } catch (Exception e) {
            return String.valueOf(raw);
        }
    }
}
