package com.octopus.wallet;

import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.EditText;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * dApp origin allowlist: add hosts, revoke access per site. Revoking removes
 * the persisted permission immediately; the in-app browser re-checks the
 * allowlist on every request, so live sessions for a revoked origin stop
 * working without restarting the app.
 */
public class DappOriginsActivity extends BaseTxActivity {

    private RecyclerView originsRecyclerView;
    private TextView emptyView;
    private final DappSessionManager sessions = new DappSessionManager();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        setTheme(ThemeManager.resolveThemeRes(this));
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_dapp_origins);
        setupToolbar(R.id.origins_toolbar, "DApp Origins");

        EditText hostInput = findViewById(R.id.origins_host_input);
        originsRecyclerView = findViewById(R.id.origins_list);
        originsRecyclerView.setLayoutManager(new LinearLayoutManager(this));

        findViewById(R.id.origins_add_button).setOnClickListener(v -> {
            String host = DappOriginStore.normalizeHost(hostInput.getText() == null ? "" : hostInput.getText().toString());
            if (host.isEmpty()) {
                showError("Invalid host");
                return;
            }
            DappOriginStore.addOrigin(this, host);
            hostInput.setText("");
            renderOrigins();
            showSuccess("Origin added: " + host);
        });

        renderOrigins();
    }

    private void renderOrigins() {
        List<String> origins = new ArrayList<>(DappOriginStore.getAllowedOrigins(this));
        Collections.sort(origins);
        originsRecyclerView.setAdapter(new OriginsAdapter(origins));
    }

    private void revoke(String host) {
        if (host == null || host.trim().isEmpty()) return;
        sessions.revoke(this, host);
        renderOrigins();
        showSuccess("Access revoked: " + host);
    }

    private final class OriginsAdapter extends RecyclerView.Adapter<OriginsAdapter.VH> {
        private final List<String> items;

        OriginsAdapter(List<String> items) {
            this.items = items;
        }

        @NonNull
        @Override
        public VH onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
            View view = LayoutInflater.from(parent.getContext())
                    .inflate(R.layout.item_dapp_origin, parent, false);
            return new VH(view);
        }

        @Override
        public void onBindViewHolder(@NonNull VH holder, int position) {
            String host = items.get(position);
            holder.host.setText(host);
            holder.revoke.setOnClickListener(v -> revoke(host));
            holder.itemView.setOnLongClickListener(v -> {
                revoke(host);
                return true;
            });
        }

        @Override
        public int getItemCount() {
            return items.size();
        }

        final class VH extends RecyclerView.ViewHolder {
            final TextView host;
            final View revoke;

            VH(View itemView) {
                super(itemView);
                host = itemView.findViewById(R.id.origin_host);
                revoke = itemView.findViewById(R.id.origin_revoke);
            }
        }
    }
}
