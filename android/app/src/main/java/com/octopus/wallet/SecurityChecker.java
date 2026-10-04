package com.octopus.wallet;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.util.Log;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;

/**
 * Performs startup security checks: root detection, emulator detection.
 * Shown as a non-dismissible warning dialog when risks are found.
 */
public final class SecurityChecker {

    private static final String TAG = "SecurityChecker";

    private static final String[] SU_PATHS = {
            "/system/bin/su", "/system/xbin/su", "/sbin/su",
            "/system/su", "/system/bin/.ext/.su", "/system/usr/we-need-root/su-backup",
            "/data/local/xbin/su", "/data/local/bin/su", "/data/local/su",
            "/su/bin/su"
    };

    private static final String[] ROOT_PACKAGES = {
            "com.topjohnwu.magisk",
            "com.noshufou.android.su",
            "com.thirdparty.superuser",
            "eu.chainfire.supersu",
            "com.koushikdutta.superuser",
            "com.zachspong.temprootremovejb",
            "com.ramdroid.appquarantine"
    };

    private SecurityChecker() {}

    // ── Public API ─────────────────────────────────────────────────────────

    /**
     * Performs all security checks and shows a warning dialog if risks are found.
     * The dialog is non-cancellable but allows the user to proceed anyway after
     * acknowledging the risk.
     *
     * @param activity the current Activity used to show the dialog
     */
    public static void performStartupCheck(Activity activity) {
        if (activity == null || activity.isFinishing() || activity.isDestroyed()) return;

        StringBuilder risks = new StringBuilder();

        if (isEmulator()) {
            risks.append("• This device appears to be an emulator or virtual device.\n");
        }
        if (isSuBinaryPresent()) {
            risks.append("• Root binary (su) detected on this device.\n");
        }
        if (hasTestKeys()) {
            risks.append("• Device is running with test-keys (not production-signed ROM).\n");
        }
        if (isRootPackageInstalled(activity)) {
            risks.append("• A root management application is installed on this device.\n");
        }

        if (risks.length() == 0) {
            return; // All clear
        }

        String message = "Security risks detected on this device:\n\n" + risks.toString().trim()
                + "\n\nUsing a crypto wallet on a potentially compromised device may expose "
                + "your private keys and funds. Proceed at your own risk.";

        activity.runOnUiThread(() -> {
            if (activity.isFinishing() || activity.isDestroyed()) return;
            Intent intent = new Intent(activity, ConfirmActionActivity.class);
            intent.putExtra(ConfirmActionActivity.EXTRA_TITLE, "⚠ Security Warning");
            intent.putExtra(ConfirmActionActivity.EXTRA_MESSAGE, message);
            intent.putExtra(ConfirmActionActivity.EXTRA_POSITIVE, "I Understand, Proceed");
            intent.putExtra(ConfirmActionActivity.EXTRA_NEGATIVE, "Exit App");
            intent.putExtra(ConfirmActionActivity.EXTRA_REQUIRE_EXPLICIT, true);
            intent.putExtra(ConfirmActionActivity.EXTRA_NEGATIVE_FINISH_AFFINITY, true);
            activity.startActivity(intent);
        });
    }

    // ── Detection methods ──────────────────────────────────────────────────

    public static boolean isEmulator() {
        String fingerprint = Build.FINGERPRINT;
        if (fingerprint != null) {
            String fp = fingerprint.toLowerCase();
            if (fp.startsWith("generic") || fp.startsWith("unknown")
                    || fp.contains("emulator") || fp.contains("sdk_gphone")
                    || fp.contains("vbox") || fp.contains("test-keys")) {
                return true;
            }
        }
        if ("goldfish".equals(Build.HARDWARE) || "ranchu".equals(Build.HARDWARE)) {
            return true;
        }
        if (Build.PRODUCT != null) {
            String product = Build.PRODUCT.toLowerCase();
            if (product.contains("sdk") || product.contains("emulator")
                    || product.contains("simulator") || product.contains("vbox")) {
                return true;
            }
        }
        if (Build.MODEL != null) {
            String model = Build.MODEL.toLowerCase();
            if (model.contains("emulator") || model.contains("android sdk")) {
                return true;
            }
        }
        return false;
    }

    public static boolean isSuBinaryPresent() {
        for (String path : SU_PATHS) {
            if (new File(path).exists()) {
                Log.w(TAG, "su binary found at: " + path);
                return true;
            }
        }
        return canRunSuCommand();
    }

    public static boolean hasTestKeys() {
        String tags = Build.TAGS;
        return tags != null && tags.contains("test-keys");
    }

    public static boolean isRootPackageInstalled(Context context) {
        if (context == null) return false;
        for (String pkg : ROOT_PACKAGES) {
            try {
                context.getPackageManager().getPackageInfo(pkg, 0);
                Log.w(TAG, "Root package found: " + pkg);
                return true;
            } catch (Exception ignored) {
            }
        }
        return false;
    }

    public static boolean isRooted(Context context) {
        return isSuBinaryPresent() || hasTestKeys() || isRootPackageInstalled(context);
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    private static boolean canRunSuCommand() {
        Process process = null;
        try {
            process = Runtime.getRuntime().exec(new String[]{"/system/xbin/which", "su"});
            BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
            String output = reader.readLine();
            return output != null && !output.trim().isEmpty();
        } catch (Exception ignored) {
            return false;
        } finally {
            if (process != null) {
                try { process.destroy(); } catch (Exception ignored) {}
            }
        }
    }
}
