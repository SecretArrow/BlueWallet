package com.octopus.wallet;

import android.content.Intent;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;
import android.widget.TextView;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import com.google.android.material.appbar.MaterialToolbar;

import java.util.ArrayList;
import java.util.List;

public class WalletsMenuActivity extends AppCompatActivity {

    private final ActivityResultLauncher<Intent> addWalletLauncher =
            registerForActivityResult(new ActivityResultContracts.StartActivityForResult(), result -> {
                if (result.getResultCode() == RESULT_OK && result.getData() != null) {
                    Intent data = new Intent();
                    data.putExtra("wallet_added", true);
                    if (result.getData().hasExtra("wallet_id")) {
                        data.putExtra("wallet_id", result.getData().getStringExtra("wallet_id"));
                    }
                    setResult(RESULT_OK, data);
                    finish();
                }
            });

    @Override
    protected void onResume() {
        super.onResume();
        SessionLockActivity.recordActivity(this);
    }

    @Override
    protected void onPause() {
        super.onPause();
        SessionLockActivity.recordActivity(this);
    }

    @Override
    public void onUserInteraction() {
        super.onUserInteraction();
        SessionLockActivity.recordActivity(this);
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        setTheme(ThemeManager.resolveThemeRes(this));
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_wallets);

        MaterialToolbar toolbar = findViewById(R.id.wallets_toolbar);
        setSupportActionBar(toolbar);
        if (getSupportActionBar() != null) {
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
            getSupportActionBar().setDisplayShowHomeEnabled(true);
            getSupportActionBar().setTitle("Wallets");
        }
        toolbar.setNavigationOnClickListener(v -> finish());

        RecyclerView recyclerView = findViewById(R.id.wallets_list);
        recyclerView.setLayoutManager(new LinearLayoutManager(this));

        // Create menu items with icons
        List<WalletMenuItem> items = new ArrayList<>();
        items.add(new WalletMenuItem("Add Account", R.drawable.ic_wallet));
        items.add(new WalletMenuItem("View Keys", R.drawable.ic_lock));

        recyclerView.setAdapter(new WalletMenuAdapter(items, item -> {
            if ("Add Account".equals(item.title)) {
                addWalletLauncher.launch(new Intent(this, AddWalletActivity.class));
            } else if ("View Keys".equals(item.title)) {
                startActivity(new Intent(this, WalletsActivity.class));
            }
        }));
    }

    /**
     * Menu item data class
     */
    private static class WalletMenuItem {
        final String title;
        final int iconRes;

        WalletMenuItem(String title, int iconRes) {
            this.title = title;
            this.iconRes = iconRes;
        }
    }

    /**
     * Click listener interface
     */
    private interface OnWalletMenuItemClickListener {
        void onItemClick(WalletMenuItem item);
    }

    /**
     * Custom RecyclerView adapter with 44dp circle icon + title + divider
     */
    private static class WalletMenuAdapter extends RecyclerView.Adapter<WalletMenuAdapter.VH> {
        private final List<WalletMenuItem> items;
        private final OnWalletMenuItemClickListener listener;

        WalletMenuAdapter(List<WalletMenuItem> items, OnWalletMenuItemClickListener listener) {
            this.items = items;
            this.listener = listener;
        }

        @NonNull
        @Override
        public VH onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
            View view = LayoutInflater.from(parent.getContext())
                    .inflate(R.layout.item_wallet_menu, parent, false);
            return new VH(view);
        }

        @Override
        public void onBindViewHolder(@NonNull VH holder, int position) {
            WalletMenuItem item = items.get(position);
            holder.title.setText(item.title);
            holder.icon.setImageResource(item.iconRes);
            holder.itemView.setOnClickListener(v -> listener.onItemClick(item));
        }

        @Override
        public int getItemCount() {
            return items.size();
        }

        static class VH extends RecyclerView.ViewHolder {
            final ImageView icon;
            final TextView title;

            VH(View itemView) {
                super(itemView);
                icon = itemView.findViewById(R.id.wallet_menu_icon);
                title = itemView.findViewById(R.id.wallet_menu_title);
            }
        }
    }
}
