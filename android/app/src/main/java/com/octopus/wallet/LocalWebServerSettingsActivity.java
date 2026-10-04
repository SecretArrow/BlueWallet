package com.octopus.wallet;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.view.View;
import android.widget.Button;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;
import androidx.core.content.ContextCompat;

import com.google.android.material.appbar.MaterialToolbar;
import com.google.android.material.card.MaterialCardView;

/**
 * Settings screen for the Local Web Server feature.
 *
 * <p>Shows a toggle to enable/disable the server, the server URL, and the
 * auth token.  Users can copy the token, regenerate it, and open the browser
 * to test the connection.</p>
 */
public class LocalWebServerSettingsActivity extends AppCompatActivity {

    private Switch serverToggle;
    private MaterialCardView serverInfoCard;
    private TextView serverUrlText;
    private TextView authTokenText;
    private Button copyTokenButton;
    private Button regenerateTokenButton;
    private Button openBrowserButton;
    private TextView statusText;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        setTheme(ThemeManager.resolveThemeRes(this));
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_local_web_server_settings);

        // Toolbar
        MaterialToolbar toolbar = findViewById(R.id.lws_toolbar);
        setSupportActionBar(toolbar);
        if (getSupportActionBar() != null) {
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
            getSupportActionBar().setTitle("Local Web Server");
        }
        toolbar.setNavigationOnClickListener(v -> finish());

        // Views
        serverToggle = findViewById(R.id.lws_toggle);
        serverInfoCard = findViewById(R.id.lws_info_card);
        serverUrlText = findViewById(R.id.lws_url_text);
        authTokenText = findViewById(R.id.lws_token_text);
        copyTokenButton = findViewById(R.id.lws_copy_token_button);
        regenerateTokenButton = findViewById(R.id.lws_regenerate_button);
        openBrowserButton = findViewById(R.id.lws_open_browser_button);
        statusText = findViewById(R.id.lws_status_text);

        // Set static URL
        serverUrlText.setText("http://localhost:" + LocalWebServerStore.PORT);

        // Load current state
        refreshUi();

        // Toggle listener
        serverToggle.setOnCheckedChangeListener((btn, isChecked) -> {
            LocalWebServerStore.setEnabled(this, isChecked);
            if (isChecked) {
                LocalWebServerService.startIfEnabled(this);
            } else {
                LocalWebServerService.stop(this);
            }
            refreshUi();
        });

        // Copy token
        copyTokenButton.setOnClickListener(v -> {
            String token = LocalWebServerStore.getAuthToken(this);
            ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
            if (cm != null) {
                cm.setPrimaryClip(ClipData.newPlainText("auth_token", token));
                Toast.makeText(this, "Token copied", Toast.LENGTH_SHORT).show();
            }
        });

        // Regenerate token
        regenerateTokenButton.setOnClickListener(v -> {
            String newToken = LocalWebServerStore.regenerateToken(this);
            // Restart server to apply new token
            if (LocalWebServerStore.isEnabled(this)) {
                LocalWebServerService.stop(this);
                LocalWebServerService.startIfEnabled(this);
            }
            refreshUi();
            Toast.makeText(this, "Token regenerated", Toast.LENGTH_SHORT).show();
        });

        // Open browser to status endpoint
        openBrowserButton.setOnClickListener(v -> {
            String url = "http://localhost:" + LocalWebServerStore.PORT + "/api/status";
            try {
                Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
                startActivity(intent);
            } catch (Exception e) {
                Toast.makeText(this, "No browser found", Toast.LENGTH_SHORT).show();
            }
        });
    }

    @Override
    protected void onResume() {
        super.onResume();
        SessionLockActivity.recordActivity(this);
        refreshUi();
    }

    @Override
    protected void onPause() {
        super.onPause();
        SessionLockActivity.recordActivity(this);
    }

    private void refreshUi() {
        boolean enabled = LocalWebServerStore.isEnabled(this);

        // Update toggle without triggering listener loop
        serverToggle.setOnCheckedChangeListener(null);
        serverToggle.setChecked(enabled);
        serverToggle.setOnCheckedChangeListener((btn, isChecked) -> {
            LocalWebServerStore.setEnabled(this, isChecked);
            if (isChecked) {
                LocalWebServerService.startIfEnabled(this);
            } else {
                LocalWebServerService.stop(this);
            }
            refreshUi();
        });

        // Show/hide info card
        serverInfoCard.setVisibility(enabled ? View.VISIBLE : View.GONE);

        // Status text
        if (enabled) {
            statusText.setText("● Running on http://localhost:" + LocalWebServerStore.PORT);
            statusText.setTextColor(ContextCompat.getColor(this, R.color.success_color));
        } else {
            statusText.setText("○ Server is disabled");
            statusText.setTextColor(ContextCompat.getColor(this, android.R.color.darker_gray));
        }

        // Token (only update if card visible)
        if (enabled) {
            String token = LocalWebServerStore.getAuthToken(this);
            // Show abbreviated token for security
            String display = token.length() > 16
                    ? token.substring(0, 8) + "••••••••" + token.substring(token.length() - 8)
                    : token;
            authTokenText.setText(display);
        }
    }
}
