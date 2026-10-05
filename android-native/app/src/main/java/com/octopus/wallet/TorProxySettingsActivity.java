package com.octopus.wallet;

import android.content.Context;
import android.content.DialogInterface;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.content.ContextCompat;

import com.google.android.material.appbar.MaterialToolbar;

import java.util.List;

/**
 * Settings screen for Tor and Proxy configurations.
 * Allows users to enable/disable Tor routing, choose SOCKS/HTTP proxies,
 * and dynamically add or remove custom proxy servers.
 */
public class TorProxySettingsActivity extends AppCompatActivity {

    private Switch torToggle;
    private TextView statusText;
    private LinearLayout serversListContainer;
    private Button addServerButton;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        setTheme(ThemeManager.resolveThemeRes(this));
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_tor_proxy_settings);

        // Toolbar
        MaterialToolbar toolbar = findViewById(R.id.tor_toolbar);
        setSupportActionBar(toolbar);
        if (getSupportActionBar() != null) {
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
            getSupportActionBar().setTitle("Tor & Proxy Settings");
        }
        toolbar.setNavigationOnClickListener(v -> finish());

        // Views
        torToggle = findViewById(R.id.tor_toggle);
        statusText = findViewById(R.id.tor_status_text);
        serversListContainer = findViewById(R.id.tor_servers_list);
        addServerButton = findViewById(R.id.tor_add_server_button);

        // Load UI elements
        refreshUi();

        // Toggle action
        torToggle.setOnCheckedChangeListener((btn, isChecked) -> {
            TorProxyStore.setEnabled(this, isChecked);
            refreshStatusText();
        });

        // Add custom server dialog action
        addServerButton.setOnClickListener(v -> showAddServerDialog());
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
        // Toggle setup
        boolean enabled = TorProxyStore.isEnabled(this);
        torToggle.setOnCheckedChangeListener(null);
        torToggle.setChecked(enabled);
        torToggle.setOnCheckedChangeListener((btn, isChecked) -> {
            TorProxyStore.setEnabled(this, isChecked);
            refreshStatusText();
        });

        // Status text update
        refreshStatusText();

        // Servers List update
        populateServersList();
    }

    private void refreshStatusText() {
        boolean enabled = TorProxyStore.isEnabled(this);
        if (enabled) {
            TorProxyStore.ProxyConfig active = TorProxyStore.getActiveProxyConfig(this);
            statusText.setText("● Active: " + active.type + " " + active.host + ":" + active.port);
            statusText.setTextColor(ContextCompat.getColor(this, R.color.success_color));
        } else {
            statusText.setText("○ Tor / Proxy is disabled");
            statusText.setTextColor(ContextCompat.getColor(this, android.R.color.darker_gray));
        }
    }

    private void populateServersList() {
        serversListContainer.removeAllViews();
        List<TorProxyStore.ProxyConfig> servers = TorProxyStore.getProxyServers(this);
        TorProxyStore.ProxyConfig active = TorProxyStore.getActiveProxyConfig(this);

        LayoutInflater inflater = LayoutInflater.from(this);

        for (int i = 0; i < servers.size(); i++) {
            final TorProxyStore.ProxyConfig server = servers.get(i);
            View row = inflater.inflate(R.layout.item_tor_server, serversListContainer, false);

            RadioButton radio = row.findViewById(R.id.tor_item_radio);
            TextView nameText = row.findViewById(R.id.tor_item_name);
            TextView addressText = row.findViewById(R.id.tor_item_address);
            ImageView deleteIcon = row.findViewById(R.id.tor_item_delete);

            nameText.setText(server.name);
            addressText.setText(server.type + " • " + server.host + ":" + server.port);

            // Is this row active?
            boolean isActive = server.host.equalsIgnoreCase(active.host) &&
                    server.port == active.port &&
                    server.type.equalsIgnoreCase(active.type);

            radio.setChecked(isActive);

            // Row click selects proxy
            View.OnClickListener selectListener = v -> {
                try {
                    TorProxyStore.setActiveProxy(this, server.host, server.port, server.type);
                } catch (IllegalArgumentException e) {
                    Toast.makeText(this, "Invalid proxy entry: " + e.getMessage(),
                            Toast.LENGTH_LONG).show();
                    return;
                }
                refreshUi();
                Toast.makeText(this, "Active proxy: " + server.name, Toast.LENGTH_SHORT).show();
            };

            row.setOnClickListener(selectListener);
            radio.setOnClickListener(selectListener);

            // Delete configuration
            if (!server.isDefault) {
                deleteIcon.setVisibility(View.VISIBLE);
                deleteIcon.setOnClickListener(v -> {
                    new AlertDialog.Builder(this)
                            .setTitle("Delete Proxy Server")
                            .setMessage("Are you sure you want to delete proxy server \"" + server.name + "\"?")
                            .setPositiveButton("Delete", (dialog, which) -> {
                                boolean deleted = TorProxyStore.removeProxyServer(this, server.host, server.port);
                                if (deleted) {
                                    // If deleted server was active, fallback to default Orbot SOCKS
                                    if (isActive) {
                                        TorProxyStore.setActiveProxy(this, "127.0.0.1", 9050, "SOCKS");
                                    }
                                    refreshUi();
                                    Toast.makeText(this, "Server deleted", Toast.LENGTH_SHORT).show();
                                }
                            })
                            .setNegativeButton("Cancel", null)
                            .show();
                });
            } else {
                deleteIcon.setVisibility(View.GONE);
            }

            serversListContainer.addView(row);
        }
    }

    private void showAddServerDialog() {
        LayoutInflater inflater = LayoutInflater.from(this);
        View dialogView = inflater.inflate(R.layout.dialog_add_proxy, null);

        final EditText nameInput = dialogView.findViewById(R.id.proxy_name_input);
        final EditText hostInput = dialogView.findViewById(R.id.proxy_host_input);
        final EditText portInput = dialogView.findViewById(R.id.proxy_port_input);
        final RadioGroup typeGroup = dialogView.findViewById(R.id.proxy_type_group);

        AlertDialog dialog = new AlertDialog.Builder(this)
                .setView(dialogView)
                .setPositiveButton("Add", null) // Set null first to prevent auto dismissal
                .setNegativeButton("Cancel", null)
                .create();

        dialog.show();

        // Custom positive click for strict input validation
        dialog.getButton(DialogInterface.BUTTON_POSITIVE).setOnClickListener(v -> {
            String name = nameInput.getText().toString().trim();
            String host = hostInput.getText().toString().trim();
            String portStr = portInput.getText().toString().trim();

            if (name.isEmpty()) {
                nameInput.setError("Server name cannot be empty");
                return;
            }
            if (host.isEmpty()) {
                hostInput.setError("Host cannot be empty");
                return;
            }
            if (portStr.isEmpty()) {
                portInput.setError("Port cannot be empty");
                return;
            }

            int port;
            try {
                port = Integer.parseInt(portStr);
                if (port < 1 || port > 65535) {
                    portInput.setError("Port must be between 1 and 65535");
                    return;
                }
            } catch (NumberFormatException e) {
                portInput.setError("Invalid port format");
                return;
            }

            // Find selected type SOCKS or HTTP
            String type = "SOCKS";
            if (typeGroup.getCheckedRadioButtonId() == R.id.proxy_type_http) {
                type = "HTTP";
            }

            // Verify duplicates
            List<TorProxyStore.ProxyConfig> existing = TorProxyStore.getProxyServers(this);
            for (TorProxyStore.ProxyConfig server : existing) {
                if (server.host.equalsIgnoreCase(host) && server.port == port) {
                    Toast.makeText(this, "A proxy server with this host & port is already registered", Toast.LENGTH_LONG).show();
                    return;
                }
            }

            // Save and refresh
            TorProxyStore.ProxyConfig config = new TorProxyStore.ProxyConfig(name, host, port, type, false);
            TorProxyStore.addProxyServer(this, config);
            refreshUi();

            Toast.makeText(this, "Proxy server added successfully", Toast.LENGTH_SHORT).show();
            dialog.dismiss();
        });
    }
}
