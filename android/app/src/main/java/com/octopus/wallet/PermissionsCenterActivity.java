package com.octopus.wallet;

import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.Settings;
import android.view.View;
import android.widget.TextView;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.core.app.NotificationManagerCompat;
import androidx.core.content.ContextCompat;

public class PermissionsCenterActivity extends BaseTxActivity {
    private static final String PREFS_TX_CACHE = "tx_cache";

    private TextView notificationStatus;
    private TextView filesStatus;
    private TextView cameraStatus;
    private View permissionCard;
    private View maintenanceCard;
    private TextView maintenanceStealthCount;
    private TextView maintenanceTxCount;
    private TextView maintenanceOriginsCount;
    private TextView maintenanceHistoryCount;
    private boolean maintenanceMode;
    private Runnable pendingMaintenanceAction;

    private final ActivityResultLauncher<String> notificationPermissionLauncher =
            registerForActivityResult(new ActivityResultContracts.RequestPermission(), granted -> refreshStatuses());

    private final ActivityResultLauncher<String> cameraPermissionLauncher =
            registerForActivityResult(new ActivityResultContracts.RequestPermission(), granted -> refreshStatuses());

    private final ActivityResultLauncher<String[]> filesPermissionLauncher =
            registerForActivityResult(new ActivityResultContracts.RequestMultiplePermissions(), result -> refreshStatuses());

    private final ActivityResultLauncher<Intent> confirmLauncher =
            registerForActivityResult(new ActivityResultContracts.StartActivityForResult(), result -> {
                Runnable action = pendingMaintenanceAction;
                pendingMaintenanceAction = null;
                if (action == null) {
                    return;
                }
                if (result.getResultCode() == RESULT_OK) {
                    try {
                        action.run();
                    } catch (Exception e) {
                        showError("Unable to complete maintenance action");
                    }
                }
            });

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_permissions_center);
        maintenanceMode = getIntent().getBooleanExtra("maintenance_mode", false);
        setupToolbar(R.id.permissions_toolbar, maintenanceMode ? "Cache" : "Permissions");

        notificationStatus = findViewById(R.id.permissions_notification_status);
        filesStatus = findViewById(R.id.permissions_files_status);
        cameraStatus = findViewById(R.id.permissions_camera_status);
        permissionCard = findViewById(R.id.permissions_permission_card);
        maintenanceCard = findViewById(R.id.permissions_maintenance_card);
        maintenanceStealthCount = findViewById(R.id.maintenance_stealth_count);
        maintenanceTxCount = findViewById(R.id.maintenance_tx_count);
        maintenanceOriginsCount = findViewById(R.id.maintenance_origins_count);
        maintenanceHistoryCount = findViewById(R.id.maintenance_history_count);

        findViewById(R.id.permissions_notification_button).setOnClickListener(v -> requestNotificationPermission());
        findViewById(R.id.permissions_files_button).setOnClickListener(v -> requestFilesPermission());
        findViewById(R.id.permissions_camera_button).setOnClickListener(v -> requestCameraPermission());
        findViewById(R.id.permissions_app_settings_button).setOnClickListener(v -> openAppSettings());

        findViewById(R.id.maintenance_clear_stealth_button).setOnClickListener(v ->
            confirmAndRun(
                "Clear Stealth Tasks",
                "This removes only local stealth task records. Blockchain funds are not affected.",
                () -> {
                    StealthTaskManager.clearAll(getApplicationContext());
                    showSuccess("Stealth task list cleared");
                    refreshStatuses();
                }
            ));

        findViewById(R.id.maintenance_clear_tx_button).setOnClickListener(v ->
            confirmAndRun(
                "Clear Transaction Tasks",
                "This removes only local transaction task records. Blockchain funds are not affected.",
                () -> {
                    TxTaskStore.clearAll(getApplicationContext());
                    showSuccess("Transaction task list cleared");
                    refreshStatuses();
                }
            ));

        findViewById(R.id.maintenance_reset_origins_button).setOnClickListener(v ->
            confirmAndRun(
                "Reset DApp Origins",
                "This resets allowed DApp origins to default values.",
                () -> {
                    DappOriginStore.resetToDefault(getApplicationContext());
                    showSuccess("DApp origins reset to default");
                    refreshStatuses();
                }
            ));

        findViewById(R.id.maintenance_clear_history_cache_button).setOnClickListener(v ->
            confirmAndRun(
                "Clear History List Cache",
                "This removes local history list cache. It will be reloaded from network data.",
                () -> {
                    getSharedPreferences(PREFS_TX_CACHE, MODE_PRIVATE).edit().clear().apply();
                    showSuccess("History list cache cleared");
                    refreshStatuses();
                }
            ));

        if (maintenanceCard != null) {
            maintenanceCard.setVisibility(maintenanceMode ? View.VISIBLE : View.GONE);
        }
        if (permissionCard != null) {
            permissionCard.setVisibility(maintenanceMode ? View.GONE : View.VISIBLE);
        }

        refreshStatuses();
    }

    @Override
    protected void onResume() {
        super.onResume();
        refreshStatuses();
    }

    private void requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            openAppNotificationSettings();
            return;
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                == PackageManager.PERMISSION_GRANTED) {
            showSuccess("Notification permission already granted");
            refreshStatuses();
            return;
        }
        notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS);
    }

    private void requestCameraPermission() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
                == PackageManager.PERMISSION_GRANTED) {
            showSuccess("Camera permission already granted");
            refreshStatuses();
            return;
        }
        cameraPermissionLauncher.launch(Manifest.permission.CAMERA);
    }

    private void requestFilesPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (Environment.isExternalStorageManager()) {
                showSuccess("File access permission already granted");
                refreshStatuses();
                return;
            }
            Intent intent = new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                    Uri.parse("package:" + getPackageName()));
            try {
                startActivity(intent);
            } catch (Exception e) {
                openAppSettings();
            }
            return;
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            String[] perms = new String[]{
                    Manifest.permission.READ_MEDIA_IMAGES,
                    Manifest.permission.READ_MEDIA_VIDEO,
                    Manifest.permission.READ_MEDIA_AUDIO
            };
            filesPermissionLauncher.launch(perms);
            return;
        }

        filesPermissionLauncher.launch(new String[]{
                Manifest.permission.READ_EXTERNAL_STORAGE,
                Manifest.permission.WRITE_EXTERNAL_STORAGE
        });
    }

    private void openAppSettings() {
        Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:" + getPackageName()));
        startActivity(intent);
    }

    private void openAppNotificationSettings() {
        Intent intent;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            intent = new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, getPackageName());
        } else {
            intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:" + getPackageName()));
        }
        startActivity(intent);
    }

    private void refreshStatuses() {
        notificationStatus.setText(isNotificationGranted() ? "Granted" : "Not granted");
        filesStatus.setText(isFilesGranted() ? "Granted" : "Not granted");
        cameraStatus.setText(isCameraGranted() ? "Granted" : "Not granted");
        if (maintenanceCard != null && maintenanceCard.getVisibility() == View.VISIBLE) {
            refreshMaintenanceCounts();
        }
    }

    private void refreshMaintenanceCounts() {
        maintenanceStealthCount.setText(String.valueOf(StealthTaskManager.getTasks(getApplicationContext()).size()));
        maintenanceTxCount.setText(String.valueOf(TxTaskStore.getAllTasks(getApplicationContext()).size()));
        maintenanceOriginsCount.setText(String.valueOf(DappOriginStore.getAllowedOrigins(getApplicationContext()).size()));
        maintenanceHistoryCount.setText(getSharedPreferences(PREFS_TX_CACHE, MODE_PRIVATE).getAll().isEmpty() ? "0" : "1+");
    }

    private void confirmAndRun(String title, String message, Runnable action) {
        pendingMaintenanceAction = action;
        Intent intent = new Intent(this, ConfirmActionActivity.class);
        intent.putExtra(ConfirmActionActivity.EXTRA_TITLE, title);
        intent.putExtra(ConfirmActionActivity.EXTRA_MESSAGE, message);
        intent.putExtra(ConfirmActionActivity.EXTRA_POSITIVE, "Clear");
        intent.putExtra(ConfirmActionActivity.EXTRA_NEGATIVE, "Cancel");
        confirmLauncher.launch(intent);
    }

    private boolean isNotificationGranted() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                    == PackageManager.PERMISSION_GRANTED;
        }
        return NotificationManagerCompat.from(this).areNotificationsEnabled();
    }

    private boolean isFilesGranted() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            return Environment.isExternalStorageManager();
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_IMAGES) == PackageManager.PERMISSION_GRANTED
                    || ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_VIDEO) == PackageManager.PERMISSION_GRANTED
                    || ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_AUDIO) == PackageManager.PERMISSION_GRANTED;
        }
        return ContextCompat.checkSelfPermission(this, Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED;
    }

    private boolean isCameraGranted() {
        return ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
                == PackageManager.PERMISSION_GRANTED;
    }
}
