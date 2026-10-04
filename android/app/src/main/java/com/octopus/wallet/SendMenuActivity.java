package com.octopus.wallet;

import android.content.Intent;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import java.util.ArrayList;
import java.util.List;

public class SendMenuActivity extends BaseTxActivity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_send_menu);
        setupToolbar(R.id.send_menu_toolbar, "Send Menu");

        RecyclerView recyclerView = findViewById(R.id.send_menu_recycler);
        if (recyclerView == null) return;

        List<MenuItem> items = new ArrayList<>();
        items.add(new MenuItem("Send", "Send OCT to an address", R.drawable.ic_send, SendActivity.class));
        items.add(new MenuItem("Stealth Send", "Private stealth transaction", R.drawable.ic_stealth, StealthSendActivity.class));
        items.add(new MenuItem("Encrypt Balance", "Move balance to encrypted mode", R.drawable.ic_encrypt, EncryptBalanceActivity.class));
        items.add(new MenuItem("Decrypt Balance", "Return encrypted balance to public", R.drawable.ic_decrypt, DecryptBalanceActivity.class));
        items.add(new MenuItem("Transactions Manager", "View all queued and completed transactions", R.drawable.ic_detail_actions, TransactionsManagerActivity.class));

        recyclerView.setLayoutManager(new LinearLayoutManager(this));
        recyclerView.setAdapter(new MenuAdapter(items));
    }

    private void openItem(MenuItem item) {
        if (item.targetClass != null) {
            startActivity(new Intent(this, item.targetClass));
        }
    }

    // ── Data model ─────────────────────────────────────────────────────────

    static final class MenuItem {
        final String title;
        final String subtitle;
        final int iconRes;
        final Class<?> targetClass;

        MenuItem(String title, String subtitle, int iconRes, Class<?> targetClass) {
            this.title = title;
            this.subtitle = subtitle;
            this.iconRes = iconRes;
            this.targetClass = targetClass;
        }
    }

    // ── RecyclerView Adapter ───────────────────────────────────────────────

    final class MenuAdapter extends RecyclerView.Adapter<MenuAdapter.VH> {
        private final List<MenuItem> items;

        MenuAdapter(List<MenuItem> items) {
            this.items = items;
        }

        @NonNull
        @Override
        public VH onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
            View v = LayoutInflater.from(parent.getContext())
                    .inflate(R.layout.item_send_menu_row, parent, false);
            return new VH(v);
        }

        @Override
        public void onBindViewHolder(@NonNull VH holder, int position) {
            MenuItem item = items.get(position);
            holder.titleText.setText(item.title);
            holder.subtitleText.setText(item.subtitle);
            holder.iconView.setImageResource(item.iconRes);
            holder.itemView.setOnClickListener(v -> openItem(item));
        }

        @Override
        public int getItemCount() {
            return items.size();
        }

        final class VH extends RecyclerView.ViewHolder {
            final ImageView iconView;
            final TextView titleText;
            final TextView subtitleText;

            VH(View v) {
                super(v);
                iconView = v.findViewById(R.id.send_menu_icon);
                titleText = v.findViewById(R.id.send_menu_title);
                subtitleText = v.findViewById(R.id.send_menu_subtitle);
            }
        }
    }
}
