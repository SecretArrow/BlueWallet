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

public class DappOriginsActivity extends BaseTxActivity {

    private RecyclerView originsRecyclerView;

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
        if (origins.isEmpty()) {
            origins.add("No origins yet");
        }
        originsRecyclerView.setAdapter(new OriginsAdapter(origins));
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
                    .inflate(R.layout.spinner_item_wallet, parent, false);
            return new VH(view);
        }

        @Override
        public void onBindViewHolder(@NonNull VH holder, int position) {
            String host = items.get(position);
            holder.text.setText(host);
            holder.itemView.setOnLongClickListener(v -> {
                if (host.trim().isEmpty() || "No origins yet".equals(host)) {
                    return true;
                }
                DappOriginStore.removeOrigin(DappOriginsActivity.this, host);
                renderOrigins();
                showSuccess("Origin removed: " + host);
                return true;
            });
        }

        @Override
        public int getItemCount() {
            return items.size();
        }

        final class VH extends RecyclerView.ViewHolder {
            final TextView text;
            VH(View itemView) {
                super(itemView);
                // spinner_item_wallet uses android:id/text1
                if (itemView instanceof TextView) {
                    text = (TextView) itemView;
                } else {
                    text = itemView.findViewById(android.R.id.text1);
                }
            }
        }
    }
}
