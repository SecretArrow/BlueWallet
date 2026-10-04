package com.octopus.wallet;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;

import androidx.annotation.NonNull;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import java.util.ArrayList;
import java.util.List;

/**
 * Centralized permission management for Android 8.0 (API 26) to latest.
 * Handles runtime permission requests with proper lifecycle management.
 */
public class PermissionManager {

    // Permission request codes
    public static final int REQUEST_CAMERA = 1001;
    public static final int REQUEST_NOTIFICATIONS = 1002;
    public static final int REQUEST_STORAGE = 1003;
    public static final int REQUEST_MULTIPLE = 1004;

    private PermissionManager() {
        // Utility class
    }

    /**
     * Check if camera permission is granted.
     */
    public static boolean hasCameraPermission(Context context) {
        return ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA)
                == PackageManager.PERMISSION_GRANTED;
    }

    /**
     * Check if notification permission is granted (Android 13+).
     */
    public static boolean hasNotificationPermission(Context context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS)
                    == PackageManager.PERMISSION_GRANTED;
        }
        return true; // Not required on Android 12 and below
    }

    /**
     * Check if storage permission is granted (varies by Android version).
     */
    public static boolean hasStoragePermission(Context context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // Android 13+ uses granular media permissions
            return ContextCompat.checkSelfPermission(context, Manifest.permission.READ_MEDIA_IMAGES)
                    == PackageManager.PERMISSION_GRANTED;
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10-12 uses scoped storage
            return true; // No permission needed for app's own files
        } else {
            // Android 8-9 needs READ_EXTERNAL_STORAGE
            return ContextCompat.checkSelfPermission(context, Manifest.permission.READ_EXTERNAL_STORAGE)
                    == PackageManager.PERMISSION_GRANTED;
        }
    }

    /**
     * Request camera permission.
     */
    public static void requestCameraPermission(@NonNull Activity activity) {
        ActivityCompat.requestPermissions(activity,
                new String[]{Manifest.permission.CAMERA},
                REQUEST_CAMERA);
    }

    /**
     * Request notification permission (Android 13+).
     */
    public static void requestNotificationPermission(@NonNull Activity activity) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ActivityCompat.requestPermissions(activity,
                    new String[]{Manifest.permission.POST_NOTIFICATIONS},
                    REQUEST_NOTIFICATIONS);
        }
    }

    /**
     * Request storage permission (varies by Android version).
     */
    public static void requestStoragePermission(@NonNull Activity activity) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // Android 13+ - request media permissions
            ActivityCompat.requestPermissions(activity,
                    new String[]{
                            Manifest.permission.READ_MEDIA_IMAGES,
                            Manifest.permission.READ_MEDIA_VIDEO
                    },
                    REQUEST_STORAGE);
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10-12 - no permission needed for app's own files
            // Just return success
        } else {
            // Android 8-9 - request storage permission
            ActivityCompat.requestPermissions(activity,
                    new String[]{Manifest.permission.READ_EXTERNAL_STORAGE},
                    REQUEST_STORAGE);
        }
    }

    /**
     * Request multiple permissions at once.
     */
    public static void requestMultiplePermissions(@NonNull Activity activity,
                                                   @NonNull String[] permissions,
                                                   int requestCode) {
        List<String> permissionsToRequest = new ArrayList<>();
        for (String permission : permissions) {
            if (ContextCompat.checkSelfPermission(activity, permission)
                    != PackageManager.PERMISSION_GRANTED) {
                permissionsToRequest.add(permission);
            }
        }

        if (!permissionsToRequest.isEmpty()) {
            ActivityCompat.requestPermissions(activity,
                    permissionsToRequest.toArray(new String[0]),
                    requestCode);
        }
    }

    /**
     * Check if all permissions in array are granted.
     */
    public static boolean hasAllPermissions(@NonNull Context context,
                                             @NonNull String[] permissions) {
        for (String permission : permissions) {
            if (ContextCompat.checkSelfPermission(context, permission)
                    != PackageManager.PERMISSION_GRANTED) {
                return false;
            }
        }
        return true;
    }

    /**
     * Get permissions that are not yet granted.
     */
    public static String[] getMissingPermissions(@NonNull Context context,
                                                  @NonNull String[] permissions) {
        List<String> missing = new ArrayList<>();
        for (String permission : permissions) {
            if (ContextCompat.checkSelfPermission(context, permission)
                    != PackageManager.PERMISSION_GRANTED) {
                missing.add(permission);
            }
        }
        return missing.toArray(new String[0]);
    }

    /**
     * Should show permission rationale?
     */
    public static boolean shouldShowRationale(@NonNull Activity activity,
                                               @NonNull String permission) {
        return ActivityCompat.shouldShowRequestPermissionRationale(activity, permission);
    }

    /**
     * Get user-friendly permission description.
     */
    public static String getPermissionDescription(@NonNull String permission) {
        switch (permission) {
            case Manifest.permission.CAMERA:
                return "Camera access for QR code scanning";
            case Manifest.permission.POST_NOTIFICATIONS:
                return "Notifications for transaction updates";
            case Manifest.permission.READ_EXTERNAL_STORAGE:
                return "Storage access for wallet backups";
            case Manifest.permission.READ_MEDIA_IMAGES:
                return "Photo access for QR code scanning";
            default:
                return "Permission required";
        }
    }
}
