package com.octopus.wallet;

import android.content.Intent;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.annotation.NonNull;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

public class NetworkSettingsActivity extends BaseTxActivity {

    private static final String FALLBACK_RPC = UrlSecurityValidator.DEFAULT_RPC;
    private static final String FALLBACK_EXPLORER = UrlSecurityValidator.DEFAULT_EXPLORER;

    private final List<NodeProfileStore.NodeProfile> networkItems = new ArrayList<>();
    private RecyclerView networkRecyclerView;
    private View networkEmptyText;
    private boolean settingsChanged;
    private NodeProfileStore.NodeProfile pendingDeleteProfile;

    private final ActivityResultLauncher<Intent> networkEditorLauncher =
            registerForActivityResult(new ActivityResultContracts.StartActivityForResult(), result -> {
                if (result.getResultCode() != RESULT_OK || result.getData() == null) {
                    return;
                }
                onNetworkEditorResult(result.getData());
            });

    private final ActivityResultLauncher<Intent> actionLauncher =
            registerForActivityResult(new ActivityResultContracts.StartActivityForResult(), result -> {
                if (result.getResultCode() != RESULT_OK || result.getData() == null) {
                    return;
                }
                Intent data = result.getData();
                String action = data.getStringExtra(NetworkActionActivity.EXTRA_ACTION);
                String profileName = data.getStringExtra(NetworkActionActivity.EXTRA_NAME);
                if (action == null || profileName == null) {
                    return;
                }
                NodeProfileStore.NodeProfile profile =
                        NodeProfileStore.findByName(networkItems, profileName);
                if (profile == null) {
                    return;
                }
                if (NetworkActionActivity.ACTION_ACTIVATE.equals(action)) {
                    if (activateProfile(profile)) {
                        showSuccess("Network activated");
                    }
                    return;
                }
                if (NetworkActionActivity.ACTION_EDIT.equals(action)) {
                    Intent intent = new Intent(this, AddNetworkActivity.class);
                    intent.putExtra(AddNetworkActivity.EXTRA_EDITING, true);
                    intent.putExtra(AddNetworkActivity.EXTRA_NAME, profile.name);
                    intent.putExtra(AddNetworkActivity.EXTRA_RPC, profile.rpcUrl);
                    intent.putExtra(AddNetworkActivity.EXTRA_EXPLORER, profile.explorerUrl);
                    networkEditorLauncher.launch(intent);
                    return;
                }
                if (NetworkActionActivity.ACTION_DELETE.equals(action)) {
                    confirmDelete(profile);
                }
            });

    private final ActivityResultLauncher<Intent> confirmLauncher =
            registerForActivityResult(new ActivityResultContracts.StartActivityForResult(), result -> {
                NodeProfileStore.NodeProfile profile = pendingDeleteProfile;
                pendingDeleteProfile = null;
                if (profile == null) {
                    return;
                }
                if (result.getResultCode() == RESULT_OK) {
                    deleteProfile(profile);
                }
            });

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        setTheme(ThemeManager.resolveThemeRes(this));
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_network_settings);
        setupToolbar(R.id.network_toolbar, "Networks");

        networkRecyclerView = findViewById(R.id.network_list_view);
        networkRecyclerView.setLayoutManager(new LinearLayoutManager(this));
        networkEmptyText = findViewById(R.id.network_empty_text);
        findViewById(R.id.network_add_button).setOnClickListener(v -> {
            Intent intent = new Intent(this, AddNetworkActivity.class);
            intent.putExtra(AddNetworkActivity.EXTRA_EDITING, false);
            networkEditorLauncher.launch(intent);
        });

        loadNetworks();
    }

    @Override
    public void finish() {
        if (settingsChanged) {
            Intent data = new Intent();
            data.putExtra("settings_changed", true);
            setResult(RESULT_OK, data);
        }
        super.finish();
    }

    private void loadNetworks() {
        String currentRpc = FALLBACK_RPC;
        String currentExplorer = FALLBACK_EXPLORER;
        try {
            JSONObject info = new JSONObject(OctraNative.getInstance().getWalletInfo());
            if (!info.has("error")) {
                currentRpc = info.optString("rpc_url", FALLBACK_RPC);
                currentExplorer = info.optString("explorer_url", FALLBACK_EXPLORER);
            }
        } catch (Exception ignored) {
        }

        NodeProfileStore.ensureDefault(this, currentRpc, currentExplorer);

        networkItems.clear();
        networkItems.addAll(NodeProfileStore.getProfiles(this));
        Collections.sort(networkItems, Comparator.comparing(item -> item.name.toLowerCase()));

        networkRecyclerView.setAdapter(new NetworkListAdapter());
        networkEmptyText.setVisibility(networkItems.isEmpty() ? View.VISIBLE : View.GONE);
    }

    private void showNetworkActions(NodeProfileStore.NodeProfile profile) {
        Intent intent = new Intent(this, NetworkActionActivity.class);
        String selectedName = NodeProfileStore.getSelectedName(this);
        intent.putExtra(NetworkActionActivity.EXTRA_IS_ACTIVE, profile.name.equals(selectedName));
        intent.putExtra(NetworkActionActivity.EXTRA_NAME, profile.name);
        actionLauncher.launch(intent);
    }

    private void onNetworkEditorResult(Intent data) {
        boolean editing = data.getBooleanExtra(AddNetworkActivity.EXTRA_EDITING, false);
        String name = data.getStringExtra(AddNetworkActivity.EXTRA_NAME);
        String rpc = data.getStringExtra(AddNetworkActivity.EXTRA_RPC);
        String explorer = data.getStringExtra(AddNetworkActivity.EXTRA_EXPLORER);

        if (name == null || name.trim().isEmpty() || rpc == null || rpc.trim().isEmpty()) {
            showError("Invalid network data");
            return;
        }

        if (editing) {
            NodeProfileStore.updateProfile(this, name, rpc, explorer);
            String selectedName = NodeProfileStore.getSelectedName(this);
            if (name.equals(selectedName)) {
                if (!activateProfile(new NodeProfileStore.NodeProfile(name, rpc, explorer))) {
                    return;
                }
            }
            loadNetworks();
            showSuccess("Network updated");
            return;
        }

        NodeProfileStore.NodeProfile added = NodeProfileStore.addProfile(this, name, rpc, explorer);
        if (!activateProfile(added)) {
            return;
        }
        loadNetworks();
        showSuccess("Network added");
    }

    private void confirmDelete(NodeProfileStore.NodeProfile profile) {
        pendingDeleteProfile = profile;
        Intent intent = new Intent(this, ConfirmActionActivity.class);
        intent.putExtra(ConfirmActionActivity.EXTRA_TITLE, "Delete Network");
        intent.putExtra(ConfirmActionActivity.EXTRA_MESSAGE, "Delete " + profile.name + "?");
        intent.putExtra(ConfirmActionActivity.EXTRA_POSITIVE, "Delete");
        intent.putExtra(ConfirmActionActivity.EXTRA_NEGATIVE, "Cancel");
        confirmLauncher.launch(intent);
    }

    private void deleteProfile(NodeProfileStore.NodeProfile profile) {
        String selectedNameBefore = NodeProfileStore.getSelectedName(this);
        if (!NodeProfileStore.removeProfile(this, profile.name)) {
            showError("At least one network must remain");
            return;
        }

        if (profile.name.equals(selectedNameBefore)) {
            List<NodeProfileStore.NodeProfile> updated = NodeProfileStore.getProfiles(this);
            String selectedAfter = NodeProfileStore.getSelectedName(this);
            NodeProfileStore.NodeProfile next = NodeProfileStore.findByName(updated, selectedAfter);
            if (next != null && !activateProfile(next)) {
                return;
            }
        }

        loadNetworks();
        showSuccess("Network deleted");
    }

    private boolean activateProfile(NodeProfileStore.NodeProfile profile) {
        try {
            String result = OctraNative.getInstance().saveSettings(profile.rpcUrl, profile.explorerUrl);
            JSONObject json = new JSONObject(result);
            if (json.has("error")) {
                showError(json.optString("error", "Failed to activate network"));
                return false;
            }

            NodeProfileStore.setSelectedName(this, profile.name);
            settingsChanged = true;
            loadNetworks();
            return true;
        } catch (Exception e) {
            showError("Failed to activate network");
            return false;
        }
    }

    private final class NetworkListAdapter extends RecyclerView.Adapter<NetworkListAdapter.VH> {
        @NonNull
        @Override
        public VH onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
            View view = LayoutInflater.from(NetworkSettingsActivity.this)
                    .inflate(R.layout.item_network_profile, parent, false);
            return new VH(view);
        }

        @Override
        public void onBindViewHolder(@NonNull VH holder, int position) {
            NodeProfileStore.NodeProfile item = networkItems.get(position);
            holder.name.setText(item.name);
            holder.rpc.setText(item.rpcUrl);
            holder.explorer.setText(item.explorerUrl == null || item.explorerUrl.trim().isEmpty()
                    ? "Explorer: -"
                    : item.explorerUrl);

            String selectedName = NodeProfileStore.getSelectedName(NetworkSettingsActivity.this);
            holder.activeBadge.setVisibility(item.name.equals(selectedName) ? View.VISIBLE : View.GONE);
            holder.itemView.setOnClickListener(v -> showNetworkActions(item));
        }

        @Override
        public int getItemCount() {
            return networkItems.size();
        }

        final class VH extends RecyclerView.ViewHolder {
            final TextView name;
            final TextView rpc;
            final TextView explorer;
            final TextView activeBadge;

            VH(View itemView) {
                super(itemView);
                name = itemView.findViewById(R.id.network_item_name);
                rpc = itemView.findViewById(R.id.network_item_rpc);
                explorer = itemView.findViewById(R.id.network_item_explorer);
                activeBadge = itemView.findViewById(R.id.network_item_active_badge);
            }
        }
    }
}
